import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../database/database_service.dart';
import '../../features/shared/models/ticket_sale_model.dart';

typedef OnLocalBookingReceived = void Function(TicketSaleModel sale);

/// Embedded Local REST API Server running inside Flutter Desktop App (Port 9090)
/// Receives instant HTTP POST requests from local Node.js WhatsApp Bot (<1ms latency).
class LocalApiServer {
  LocalApiServer._internal();
  static final LocalApiServer instance = LocalApiServer._internal();

  HttpServer? _server;
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  int _serverPort = 9090;

  OnLocalBookingReceived? onBookingReceived;

  /// Start the embedded HTTP REST API Server
  Future<void> start({int port = 9090, OnLocalBookingReceived? onBooking}) async {
    if (_isRunning) return;
    _serverPort = port;
    if (onBooking != null) onBookingReceived = onBooking;

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _serverPort);
      _isRunning = true;
      debugPrint('⚡ [LOCAL REST API] Server active at http://127.0.0.1:$_serverPort');

      _server!.listen((HttpRequest request) async {
        _handleCORS(request);

        if (request.method == 'OPTIONS') {
          request.response
            ..statusCode = HttpStatus.ok
            ..close();
          return;
        }

        final path = request.uri.path;

        if (path == '/api/v1/health' && request.method == 'GET') {
          _sendJsonResponse(request, {
            'status': 'online',
            'app': 'NagaLand TicketCore POS Counter',
            'timestamp': DateTime.now().toIso8601String(),
          });
          return;
        }

        if (path == '/api/v1/booking' && request.method == 'POST') {
          await _handleBookingPost(request);
          return;
        }

        // 404 Not Found for unrecognized routes
        request.response
          ..statusCode = HttpStatus.notFound
          ..write(jsonEncode({'error': 'Endpoint not found'}))
          ..close();
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

  void _handleCORS(HttpRequest request) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
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
      final bodyStr = await utf8.decoder.bind(request).join();
      if (bodyStr.trim().isEmpty) {
        _sendJsonResponse(request, {'error': 'Empty JSON payload'}, statusCode: HttpStatus.badRequest);
        return;
      }

      final dynamic parsedJson = jsonDecode(bodyStr);
      final List<Map<String, dynamic>> items = [];

      if (parsedJson is List) {
        for (final item in parsedJson) {
          if (item is Map<String, dynamic>) items.add(item);
        }
      } else if (parsedJson is Map<String, dynamic>) {
        items.add(parsedJson);
      }

      int successCount = 0;
      int duplicateCount = 0;
      TicketSaleModel? lastSale;

      for (final item in items) {
        final String id = item['id']?.toString() ?? 'tkt_rest_${DateTime.now().microsecondsSinceEpoch}_${items.indexOf(item)}_${item['ticketSeries']}_${item['ticketNumber']}';
        final String seriesName = item['ticketSeries']?.toString() ?? '12';
        final String ticketNum = item['ticketNumber']?.toString() ?? '';
        final String drawName = item['drawName']?.toString() ?? 'Dear 1 PM';
        final String drawDateRaw = item['drawDate']?.toString() ?? DateTime.now().toIso8601String();

        // User Directive: Allow all incoming ticket entries (even duplicate ticket numbers or names)

        final int qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final double price = (item['pricePerTicket'] as num?)?.toDouble() ?? 0.0;
        final double total = (item['totalAmount'] as num?)?.toDouble() ?? (price * qty);

        final sale = TicketSaleModel(
          id: id,
          receiptNumber: item['receiptNumber']?.toString() ?? 'REC-$seriesName-${DateTime.now().millisecondsSinceEpoch}',
          buyerName: item['buyerName']?.toString() ?? 'WhatsApp Seller',
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

        // 1. Instant Local SQLite Insert (<1ms)
        await DatabaseService.instance.insertTicketSale(sale, isSilent: true);
        successCount++;
        lastSale = sale;
      }

      // 2. Notify UI listener ONCE for instant screen refresh after batch completes
      if (lastSale != null) {
        onBookingReceived?.call(lastSale);
      }

      debugPrint('⚡ [LOCAL REST API] Received $successCount new ticket(s) & $duplicateCount duplicate(s) directly in SQLite!');
      _sendJsonResponse(request, {
        'success': true,
        'receivedCount': successCount,
        'duplicateCount': duplicateCount,
        'message': 'Processed directly in local SQLite database in <1ms'
      }, statusCode: HttpStatus.created);

    } catch (e) {
      debugPrint('⚠️ [LOCAL REST API ERROR] Failed to process booking POST: $e');
      _sendJsonResponse(request, {'error': 'Failed to process payload: $e'}, statusCode: HttpStatus.internalServerError);
    }
  }
}
