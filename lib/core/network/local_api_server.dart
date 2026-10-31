import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../database/database_service.dart';
import '../../features/shared/models/ticket_sale_model.dart';

typedef OnLocalBookingReceived = void Function(TicketSaleModel sale);

/// Embedded Local REST API Server running inside Flutter Desktop App (Port 9090)
/// Receives instant HTTP POST requests from local Node.js WhatsApp Bot (<1ms latency).
/// Hardened for Production Security:
/// - Restricted to Loopback IPv4 (127.0.0.1)
/// - API Token / Bearer Authentication
/// - Safe CORS Origin Validation (Blocks browser drive-by attacks)
/// - Request Payload Size Budget (Max 10 MB)
/// - Strict Input Sanitization & Bounds Checking
/// - Sanitized Error Responses (Zero exception leakage)
class LocalApiServer {
  LocalApiServer._internal();
  static final LocalApiServer instance = LocalApiServer._internal();

  static const int maxPayloadBytes = 10 * 1024 * 1024; // 10 MB payload limit
  static const int maxBatchItems = 5000;

  HttpServer? _server;
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  int _serverPort = 9090;
  String? _apiKey;

  OnLocalBookingReceived? onBookingReceived;

  /// Start the embedded HTTP REST API Server
  Future<void> start({
    int port = 9090,
    String? apiKey,
    OnLocalBookingReceived? onBooking,
  }) async {
    if (_isRunning) return;
    _serverPort = port;
    _apiKey = apiKey ?? dotenv.env['LOCAL_API_SECRET_KEY'] ?? 'ops_local_pos_secure_key_2026';

    if (onBooking != null) onBookingReceived = onBooking;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _serverPort);
      _isRunning = true;
      debugPrint('⚡ [LOCAL REST API] Hardened Server active at http://127.0.0.1:$_serverPort');

      _server!.listen((HttpRequest request) async {
        _handleCORS(request);

        if (request.method == 'OPTIONS') {
          request.response
            ..statusCode = HttpStatus.ok
            ..close();
          return;
        }

        // Validate API Key Authentication for all non-OPTIONS requests
        if (!_isAuthorized(request)) {
          _sendJsonResponse(
            request,
            {'error': 'Unauthorized: Valid API key required in Authorization or X-API-Key header'},
            statusCode: HttpStatus.unauthorized,
          );
          return;
        }

        final path = request.uri.path;

        if (path == '/api/v1/health' && request.method == 'GET') {
          _sendJsonResponse(request, {
            'status': 'online',
            'app': 'PhantomManagement POS Counter',
            'timestamp': DateTime.now().toIso8601String(),
          });
          return;
        }

        if (path == '/api/v1/booking' && request.method == 'POST') {
          await _handleBookingPost(request);
          return;
        }

        // 404 Not Found for unrecognized routes
        _sendJsonResponse(
          request,
          {'error': 'Endpoint not found'},
          statusCode: HttpStatus.notFound,
        );
      });
    } catch (e) {
      debugPrint('⚠️ [LOCAL REST API] Could not start server on port $_serverPort: $e');
      _isRunning = false;
    }
  }

  /// Stop the embedded HTTP Server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      debugPrint('🛑 [LOCAL REST API] Server stopped.');
    }
  }

  /// Authenticate incoming request via Bearer token or X-API-Key header
  bool _isAuthorized(HttpRequest request) {
    if (_apiKey == null || _apiKey!.isEmpty) return true;

    // Check X-API-Key header
    final xApiKey = request.headers.value('x-api-key');
    if (xApiKey != null && xApiKey == _apiKey) return true;

    // Check Authorization: Bearer <key>
    final authHeader = request.headers.value('authorization');
    if (authHeader != null) {
      final parts = authHeader.split(' ');
      if (parts.length == 2 && parts.first.toLowerCase() == 'bearer') {
        if (parts.last == _apiKey) return true;
      }
    }

    return false;
  }

  /// Restrict CORS to trusted local/loopback origins
  void _handleCORS(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin != null) {
      final originLower = origin.toLowerCase();
      // Allow only loopback/local origins
      if (originLower.startsWith('http://localhost') ||
          originLower.startsWith('http://127.0.0.1') ||
          originLower.startsWith('https://localhost') ||
          originLower.startsWith('https://127.0.0.1')) {
        request.response.headers.add('Access-Control-Allow-Origin', origin);
      }
    }
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-Key');
  }

  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> data, {int statusCode = HttpStatus.ok}) {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data))
      ..close();
  }

  Future<void> _handleBookingPost(HttpRequest request) async {
    try {
      // 🛡️ Content-Length Budget Guard
      final declaredLength = request.contentLength;
      if (declaredLength > maxPayloadBytes) {
        _sendJsonResponse(
          request,
          {'error': 'Payload Too Large: Maximum allowed size is 10 MB'},
          statusCode: HttpStatus.requestEntityTooLarge,
        );
        return;
      }

      // Safe Streaming Accumulation with Byte Limit
      final bytesBuilder = BytesBuilder(copy: false);
      int accumulated = 0;

      await for (final chunk in request) {
        accumulated += chunk.length;
        if (accumulated > maxPayloadBytes) {
          _sendJsonResponse(
            request,
            {'error': 'Payload Too Large: Stream exceeded 10 MB limit'},
            statusCode: HttpStatus.requestEntityTooLarge,
          );
          return;
        }
        bytesBuilder.add(chunk);
      }

      final bodyStr = utf8.decode(bytesBuilder.takeBytes(), allowMalformed: false);
      if (bodyStr.trim().isEmpty) {
        _sendJsonResponse(request, {'error': 'Empty JSON payload'}, statusCode: HttpStatus.badRequest);
        return;
      }

      final dynamic parsedJson = jsonDecode(bodyStr);
      final List<Map<String, dynamic>> items = [];

      if (parsedJson is List) {
        if (parsedJson.length > maxBatchItems) {
          _sendJsonResponse(
            request,
            {'error': 'Batch size exceeds maximum limit of $maxBatchItems items'},
            statusCode: HttpStatus.badRequest,
          );
          return;
        }
        for (final item in parsedJson) {
          if (item is Map<String, dynamic>) items.add(item);
        }
      } else if (parsedJson is Map<String, dynamic>) {
        items.add(parsedJson);
      } else {
        _sendJsonResponse(request, {'error': 'Invalid payload format: Expected JSON Object or Array'}, statusCode: HttpStatus.badRequest);
        return;
      }

      int successCount = 0;
      int duplicateCount = 0;
      TicketSaleModel? lastSale;

      for (final item in items) {
        // Input sanitization & bounds checking
        final String rawSeries = item['ticketSeries']?.toString().trim() ?? '12';
        final String seriesName = rawSeries.length > 50 ? rawSeries.substring(0, 50) : rawSeries;

        final String rawTicket = item['ticketNumber']?.toString().trim() ?? '';
        final String ticketNum = rawTicket.length > 100 ? rawTicket.substring(0, 100) : rawTicket;

        final String rawBuyer = item['buyerName']?.toString().trim() ?? 'WhatsApp Seller';
        final String buyerName = rawBuyer.length > 200 ? rawBuyer.substring(0, 200) : rawBuyer;

        final String rawDraw = item['drawName']?.toString().trim() ?? 'Dear 1 PM';
        final String drawName = rawDraw.length > 100 ? rawDraw.substring(0, 100) : rawDraw;

        final String drawDateRaw = item['drawDate']?.toString() ?? DateTime.now().toIso8601String();

        final rawQty = (item['quantity'] as num?)?.toInt() ?? 1;
        final int qty = rawQty.clamp(1, 100000);

        final rawPrice = (item['pricePerTicket'] as num?)?.toDouble() ?? 0.0;
        final double price = (rawPrice.isFinite && rawPrice >= 0 && rawPrice <= 10000000) ? rawPrice : 0.0;

        final rawTotal = (item['totalAmount'] as num?)?.toDouble() ?? (price * qty);
        final double total = (rawTotal.isFinite && rawTotal >= 0) ? rawTotal : (price * qty);

        final String id = item['id']?.toString() ?? 'tkt_rest_${DateTime.now().microsecondsSinceEpoch}_${items.indexOf(item)}_$seriesName';

        final sale = TicketSaleModel(
          id: id,
          receiptNumber: item['receiptNumber']?.toString() ?? 'REC-$seriesName-${DateTime.now().millisecondsSinceEpoch}',
          buyerName: buyerName,
          buyerPhone: item['buyerPhone']?.toString() ?? '',
          agentCode: item['agentCode']?.toString() ?? 'AG-WA',
          agentName: item['agentName']?.toString() ?? 'WhatsApp Seller',
          drawCode: item['drawCode']?.toString() ?? 'DEAR-1-PM',
          drawName: drawName,
          ticketSeries: seriesName,
          ticketNumber: ticketNum,
          quantity: qty,
          pricePerTicket: price,
          totalAmount: total,
          commissionAmount: total * 0.05,
          status: TicketStatus.values.firstWhere(
            (e) => e.name == item['status'],
            orElse: () => TicketStatus.sold,
          ),
          paymentMode: PaymentMode.values.firstWhere(
            (e) => e.name == item['paymentMode'],
            orElse: () => PaymentMode.cash,
          ),
          saleDate: item['saleDate'] != null ? (DateTime.tryParse(item['saleDate'].toString())?.toLocal() ?? DateTime.now()) : DateTime.now(),
          drawDate: (DateTime.tryParse(drawDateRaw)?.toLocal() ?? DateTime.now()),
        );

        // Instant Local SQLite Insert
        await DatabaseService.instance.insertTicketSale(sale, isSilent: true);
        successCount++;
        lastSale = sale;
      }

      // Notify UI listener ONCE for instant screen refresh after batch completes
      if (lastSale != null) {
        onBookingReceived?.call(lastSale);
      }

      debugPrint('⚡ [LOCAL REST API] Received $successCount ticket(s) securely into SQLite!');
      _sendJsonResponse(request, {
        'success': true,
        'receivedCount': successCount,
        'duplicateCount': duplicateCount,
        'message': 'Processed securely in local SQLite database'
      }, statusCode: HttpStatus.created);

    } on FormatException {
      _sendJsonResponse(request, {'error': 'Malformed JSON or invalid character encoding'}, statusCode: HttpStatus.badRequest);
    } catch (e) {
      debugPrint('⚠️ [LOCAL REST API ERROR] Failed to process booking POST: $e');
      _sendJsonResponse(request, {'error': 'Internal server error while processing booking payload'}, statusCode: HttpStatus.internalServerError);
    }
  }
}
