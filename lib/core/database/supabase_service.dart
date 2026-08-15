import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/shared/models/ticket_sale_model.dart';
import '../../features/shared/models/series_price_model.dart';
import '../../features/sellers/models/seller_customer_model.dart';
import 'database_service.dart';

class SupabaseService {
  SupabaseService._internal();
  static final SupabaseService instance = SupabaseService._internal();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    return Supabase.instance.client;
  }

  /// Initialize Supabase Flutter SDK dynamically from .env file
  Future<void> initialize({String? url, String? anonKey}) async {
    final targetUrl = url ?? dotenv.env['SUPABASE_URL'] ?? '';
    final targetKey = anonKey ?? dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    if (targetUrl.isEmpty || targetUrl.contains('YOUR_SUPABASE_PROJECT_ID')) {
      debugPrint('ℹ️ [SUPABASE LOG] Demo Supabase URL in .env file. Desktop running with local SQLite.');
      return;
    }


    try {
      await Supabase.initialize(
        url: targetUrl,
        // ignore: deprecated_member_use
        anonKey: targetKey,
      );
      _isInitialized = true;
      debugPrint('⚡ [SUPABASE LOG] Admin Desktop connected to Supabase Cloud!');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Could not initialize Supabase Cloud: $e');
    }
  }

  /// Real-time stream of incoming ticket sales from Seller mobile apps
  Stream<List<Map<String, dynamic>>>? streamIncomingSales() {
    if (!_isInitialized || client == null) return null;
    try {
      return client!.from('ticket_sales').stream(primaryKey: ['id']).order('saleDate', ascending: false);
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] streamIncomingSales error: $e');
      return null;
    }
  }

  /// Fetch all ticket sales from Supabase Cloud and sync them to local SQLite DB
  Future<List<TicketSaleModel>> fetchCloudSales() async {
    if (!_isInitialized || client == null) return [];
    try {
      final response = await client!.from('ticket_sales').select().order('saleDate', ascending: false);
      if (response.isEmpty) return [];

      final db = await DatabaseService.instance.database;
      final batch = db.batch();
      final List<TicketSaleModel> cloudList = [];

      for (final item in response) {
        final seriesName = item['ticketSeries'] as String? ?? '';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;

        final pricePerTicket = (item['pricePerTicket'] as num?)?.toDouble() ?? 0.0;
        final totalAmt = (item['totalAmount'] as num?)?.toDouble() ?? 0.0;
        final finalTotal = totalAmt > 0.0 ? totalAmt : (pricePerTicket * qty);

        final sale = TicketSaleModel(
          id: item['id'] as String,
          receiptNumber: item['receiptNumber'] as String? ?? '',
          buyerName: item['buyerName'] as String? ?? '',
          buyerPhone: item['buyerPhone'] as String? ?? '',
          agentCode: item['agentCode'] as String? ?? '',
          agentName: item['agentName'] as String? ?? '',
          drawCode: item['drawCode'] as String? ?? '',
          drawName: item['drawName'] as String? ?? '',
          ticketSeries: seriesName,
          ticketNumber: item['ticketNumber'] as String? ?? '',
          quantity: qty,
          pricePerTicket: pricePerTicket,
          totalAmount: finalTotal,
          commissionAmount: finalTotal * 0.05,
          status: TicketStatus.values.firstWhere(
            (e) => e.name == item['status'],
            orElse: () => TicketStatus.sold,
          ),
          paymentMode: PaymentMode.values.firstWhere(
            (e) => e.name == item['paymentMode'],
            orElse: () => PaymentMode.cash,
          ),
          saleDate: item['saleDate'] != null ? DateTime.parse(item['saleDate'].toString()) : DateTime.now(),
          drawDate: item['drawDate'] != null ? DateTime.parse(item['drawDate'].toString()) : DateTime.now(),
        );

        batch.insert(
          'ticket_sales',
          {
            'id': sale.id,
            'receiptNumber': sale.receiptNumber,
            'buyerName': sale.buyerName,
            'buyerPhone': sale.buyerPhone,
            'agentCode': sale.agentCode,
            'agentName': sale.agentName,
            'drawCode': sale.drawCode,
            'drawName': sale.drawName,
            'ticketSeries': sale.ticketSeries,
            'ticketNumber': sale.ticketNumber,
            'quantity': sale.quantity,
            'pricePerTicket': sale.pricePerTicket,
            'totalAmount': sale.totalAmount,
            'commissionAmount': sale.commissionAmount,
            'status': sale.status.name,
            'paymentMode': sale.paymentMode.name,
            'saleDate': sale.saleDate.toIso8601String(),
            'drawDate': sale.drawDate.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        cloudList.add(sale);
      }

      await batch.commit(noResult: true);
      if (cloudList.isNotEmpty) {
        debugPrint('☁️ [SUPABASE LOG] Synced ${cloudList.length} ticket sales from cloud.');
      }
      return cloudList;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Fetch cloud sales error: $e');
      return [];
    }
  }

  // In-memory queue for 10-second debounced Cloud Bulk Sync
  final List<Map<String, dynamic>> _pendingCloudSyncQueue = [];
  Timer? _cloudDebounceTimer;

  /// Save Ticket Sale: Instantly to Local SQLite DB, and Cloud bulk-sync after 10s quiet period
  Future<void> insertTicketBooking(TicketSaleModel sale) async {
    // 1. Instant Permanent Save to Local SQLite Database (Zero UI Lag)
    await DatabaseService.instance.insertTicketSale(sale);

    // 2. Queue for 10-Second Debounced Cloud Batch Sync
    if (_isInitialized && client != null) {
      _pendingCloudSyncQueue.add(_ticketSaleToMap(sale));
      _scheduleCloudBatchFlush();
    }
  }

  void _scheduleCloudBatchFlush() {
    _cloudDebounceTimer?.cancel();
    _cloudDebounceTimer = Timer(const Duration(seconds: 10), () async {
      await flushPendingTicketsToCloud();
    });
  }

  /// Flush accumulated batch of ticket sales to Supabase Cloud
  Future<void> flushPendingTicketsToCloud() async {
    if (_pendingCloudSyncQueue.isEmpty || !_isInitialized || client == null) return;
    final batch = List<Map<String, dynamic>>.from(_pendingCloudSyncQueue);
    _pendingCloudSyncQueue.clear();

    try {
      await client!.from('ticket_sales').upsert(batch);
      debugPrint('☁️ [SUPABASE 10s BATCH SYNC] Flushed ${batch.length} ticket(s) to Cloud Database!');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE 10s BATCH SYNC] Error syncing batch to cloud: $e');
      // On failure, re-queue batch
      _pendingCloudSyncQueue.insertAll(0, batch);
    }
  }

  /// Sync Seller/Customer to Supabase Cloud so Seller Mobile App can log in
  Future<void> upsertSeller(SellerCustomerModel seller) async {
    if (_isInitialized && client != null) {
      try {
        await client!.from('sellers').upsert({
          'id': seller.id,
          'name': seller.name,
          'accessKey': seller.accessKey,
          'password': seller.password,
          'phone': seller.phone,
          'isActive': seller.isActive,
          'createdAt': seller.createdAt.toIso8601String(),
        });
        debugPrint('☁️ [SUPABASE LOG] Seller "${seller.name}" (${seller.accessKey}) synced to Supabase Cloud!');
      } catch (e) {
        debugPrint('⚠️ [SUPABASE LOG] Seller cloud sync error: $e');
      }
    }
  }

  /// Delete Seller from Supabase Cloud
  Future<void> deleteSeller(String id) async {
    if (_isInitialized && client != null) {
      try {
        await client!.from('sellers').delete().eq('id', id);
        debugPrint('☁️ [SUPABASE LOG] Deleted Seller $id from Supabase Cloud');
      } catch (e) {
        debugPrint('⚠️ [SUPABASE LOG] Delete seller cloud error: $e');
      }
    }
  }

  /// Fetch all Money Collectors from Supabase Cloud
  Future<List<Map<String, dynamic>>> fetchCollectors() async {
    if (!_isInitialized || client == null) return [];
    try {
      final response = await client!.from('collectors').select().order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('⚠️ [SUPABASE] Fetch collectors cloud error: $e');
      return [];
    }
  }

  /// Save or Update Collector on Supabase Cloud
  Future<void> saveCollectorToCloud(Map<String, dynamic> collector) async {
    if (_isInitialized && client != null) {
      try {
        final cloudMap = Map<String, dynamic>.from(collector);
        if (cloudMap.containsKey('is_active')) {
          cloudMap['is_active'] = (cloudMap['is_active'] == 1 || cloudMap['is_active'] == true || cloudMap['is_active'] == '1');
        }
        await client!.from('collectors').upsert(cloudMap);
        debugPrint('☁️ [SUPABASE] Synced Collector ${collector['name']} to Cloud');
      } catch (e) {
        debugPrint('⚠️ [SUPABASE] Save collector cloud error: $e');
      }
    }
  }

  /// Fetch Collector Payment Collections from Supabase Cloud and sync to SQLite DB
  Future<List<Map<String, dynamic>>> fetchCloudCollectorPayments() async {
    if (!_isInitialized || client == null) return [];
    try {
      final response = await client!.from('collector_payments').select().order('collected_at', ascending: false);
      final List<Map<String, dynamic>> list = List<Map<String, dynamic>>.from(response);
      for (final item in list) {
        await DatabaseService.instance.insertCollectorPayment(item);
      }
      return list;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE] Fetch collector payments cloud error: $e');
      return [];
    }
  }

  /// Get Tab Permission Settings from Supabase Cloud
  Future<Map<String, bool>> getTabPermissions() async {
    if (!_isInitialized || client == null) {
      return {
        'ticket_booking': true,
        'company_forward': true,
        'result_entry': true,
        'customers_sellers': false,
        'money_collectors': false,
        'analytics': false,
        'settings': false,
      };
    }
    try {
      final List res = await client!.from('system_settings').select().eq('id', 'tab_permissions');
      if (res.isNotEmpty) {
        final Map<String, dynamic> data = res.first;
        return {
          'ticket_booking': (data['ticket_booking'] == true || data['ticket_booking'] == 1),
          'company_forward': (data['company_forward'] == true || data['company_forward'] == 1),
          'result_entry': (data['result_entry'] == true || data['result_entry'] == 1),
          'customers_sellers': (data['customers_sellers'] == true || data['customers_sellers'] == 1),
          'money_collectors': (data['money_collectors'] == true || data['money_collectors'] == 1),
          'analytics': (data['analytics'] == true || data['analytics'] == 1),
          'settings': (data['settings'] == true || data['settings'] == 1),
        };
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching tab permissions: $e');
    }
    return {
      'ticket_booking': true,
      'company_forward': true,
      'result_entry': true,
      'customers_sellers': false,
      'money_collectors': false,
      'analytics': false,
      'settings': false,
    };
  }

  Map<String, dynamic> _ticketSaleToMap(TicketSaleModel s) {
    return {
      'id': s.id,
      'receiptNumber': s.receiptNumber,
      'buyerName': s.buyerName,
      'buyerPhone': s.buyerPhone,
      'agentCode': s.agentCode,
      'agentName': s.agentName,
      'drawCode': s.drawCode,
      'drawName': s.drawName,
      'ticketSeries': s.ticketSeries,
      'ticketNumber': s.ticketNumber,
      'quantity': s.quantity,
      'pricePerTicket': s.pricePerTicket,
      'totalAmount': s.totalAmount,
      'commissionAmount': s.commissionAmount,
      'status': s.status.name,
      'paymentMode': s.paymentMode.name,
      'saleDate': s.saleDate.toIso8601String(),
      'drawDate': s.drawDate.toIso8601String(),
    };
  }

  /// Delete individual ticket sale from Supabase Cloud DB by ID
  Future<void> deleteCloudTicketSale(String id) async {
    if (!_isInitialized || client == null || id.isEmpty) return;
    try {
      await client!.from('ticket_sales').delete().eq('id', id);
      debugPrint('☁️ [SUPABASE LOG] Deleted Cloud ticket sale ID: $id');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Delete cloud ticket sale error: $e');
    }
  }

  /// Bulk delete ticket sales from Supabase Cloud DB by list of IDs
  Future<void> deleteCloudTicketSalesByIds(List<String> ids) async {
    if (!_isInitialized || client == null || ids.isEmpty) return;
    try {
      await client!.from('ticket_sales').delete().filter('id', 'in', ids);
      debugPrint('☁️ [SUPABASE LOG] Deleted ${ids.length} Cloud ticket sale(s) in bulk by IDs');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Delete cloud ticket sales by IDs error: $e');
      for (final id in ids) {
        try {
          await client!.from('ticket_sales').delete().eq('id', id);
        } catch (_) {}
      }
    }
  }

  /// Delete individual ticket sale from Supabase Cloud DB by Series & Number
  Future<void> deleteCloudTicketSaleBySeriesAndNumber(String series, String ticketNo) async {
    if (!_isInitialized || client == null) return;
    try {
      await client!
          .from('ticket_sales')
          .delete()
          .ilike('ticketSeries', series)
          .or('ticketNumber.eq.$ticketNo,ticketNumber.eq.$series $ticketNo');
      debugPrint('☁️ [SUPABASE LOG] Deleted Cloud ticket sale Series: $series, Ticket: $ticketNo');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Delete cloud ticket sale error: $e');
    }
  }

  /// Wipe all ticket sales & bookings from Supabase Cloud DB
  Future<bool> wipeCloudTicketSales() async {
    if (!_isInitialized || client == null) return false;
    try {
      await client!.from('ticket_sales').delete().neq('id', '0');
      debugPrint('🧹 [SUPABASE LOG] Cloud ticket_sales table wiped clean!');
      return true;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Cloud wipe ticket_sales error: $e');
      return false;
    }
  }

  /// Wipe all unsold tickets from Supabase Cloud DB
  Future<bool> wipeCloudUnsoldTickets() async {
    if (!_isInitialized || client == null) return false;
    try {
      await client!.from('unsold_tickets').delete().neq('id', '0');
      debugPrint('🧹 [SUPABASE LOG] Cloud unsold_tickets table wiped clean!');
      return true;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Cloud wipe unsold_tickets error: $e');
      return false;
    }
  }
  /// Sync Series Price to Supabase Cloud (Insert or Update)
  Future<void> upsertSeriesPrice(UniversalSeriesPriceModel item) async {
    if (!_isInitialized || client == null) return;
    try {
      await client!.from('series_prices').upsert({
        'id': item.id,
        'seriesName': item.seriesName,
        'ticketPrice': item.ticketPrice,
        'isActive': item.isActive,
        'createdAt': item.createdAt.toIso8601String(),
      });
      debugPrint('☁️ [SUPABASE LOG] Series "${item.seriesName}" price ₹${item.ticketPrice} synced to Cloud!');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Series price cloud sync error: $e');
    }
  }

  /// Delete Series Price from Supabase Cloud
  Future<void> deleteCloudSeriesPrice(String id) async {
    if (!_isInitialized || client == null) return;
    try {
      await client!.from('series_prices').delete().eq('id', id);
      debugPrint('☁️ [SUPABASE LOG] Deleted Cloud series price ID: $id');
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Delete cloud series price error: $e');
    }
  }

  /// Fetch all Series Prices from Supabase Cloud and sync to local SQLite
  Future<List<UniversalSeriesPriceModel>> fetchCloudSeriesPrices() async {
    if (!_isInitialized || client == null) return [];
    try {
      final response = await client!.from('series_prices').select().order('seriesName', ascending: true);
      final List<UniversalSeriesPriceModel> list = [];
      for (final item in response) {
        final model = UniversalSeriesPriceModel(
          id: item['id'] as String,
          seriesName: item['seriesName'] as String? ?? '',
          ticketPrice: (item['ticketPrice'] as num?)?.toDouble() ?? 0.0,
          isActive: (item['isActive'] == true || item['isActive'] == 1),
          createdAt: item['createdAt'] != null ? DateTime.parse(item['createdAt'].toString()) : DateTime.now(),
        );
        await DatabaseService.instance.insertSeriesPrice(model, silent: true);
        list.add(model);
      }
      debugPrint('☁️ [SUPABASE LOG] Synced ${list.length} series prices from Cloud.');
      return list;
    } catch (e) {
      debugPrint('⚠️ [SUPABASE LOG] Fetch cloud series prices error: $e');
      return [];
    }
  }
}
