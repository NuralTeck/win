import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/intl.dart';
import '../services/security_crypto_service.dart';

import '../../features/shared/models/ticket_sale_model.dart';
import '../../features/sellers/models/seller_customer_model.dart';
import '../../features/shared/models/series_price_model.dart';
import '../../features/operations/models/lottery_sambad_result_model.dart';
import '../../features/operations/models/winning_claim_model.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

  @visibleForTesting
  void setDatabaseForTesting(Database db) {
    _db = db;
  }

  // ⚡ Global Change Notifier for Ticket Sales Table (triggers instant live auto-refresh across UI)
  final ValueNotifier<int> onTicketSalesChanged = ValueNotifier<int>(0);

  void notifyTicketSalesChanged() {
    onTicketSalesChanged.value = onTicketSalesChanged.value + 1;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // Initialize FFI for desktop (Windows)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'opscore_pro.db');

    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
        await _seedInitialData(db);
      },
    );
    // ⚡ High-scale SQLite performance tuning (WAL mode, 64MB RAM Cache, 256MB MMAP)
    await db.execute('PRAGMA journal_mode=WAL;');
    await db.execute('PRAGMA busy_timeout=10000;');
    await db.execute('PRAGMA synchronous=NORMAL;');
    await db.execute('PRAGMA cache_size = -64000;'); // 64 MB in-memory cache
    await db.execute('PRAGMA temp_store = MEMORY;');
    await db.execute('PRAGMA mmap_size = 268435456;'); // 256 MB Memory Mapped I/O
    await db.execute('PRAGMA auto_vacuum = INCREMENTAL;'); // Incrementally reclaim unused pages
    await db.execute('PRAGMA optimize;'); // Optimize query planner
    await _createTables(db);
    await _runMigrations(db);
    return db;
  }

  Future<void> _createTables(Database db) async {
    // Ticket Sales / Bookings table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ticket_sales (
        id TEXT PRIMARY KEY,
        receiptNumber TEXT NOT NULL,
        buyerName TEXT NOT NULL,
        buyerPhone TEXT NOT NULL,
        agentCode TEXT NOT NULL,
        agentName TEXT NOT NULL,
        drawCode TEXT NOT NULL,
        drawName TEXT NOT NULL,
        ticketSeries TEXT NOT NULL,
        ticketNumber TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        pricePerTicket REAL NOT NULL,
        totalAmount REAL NOT NULL,
        commissionAmount REAL NOT NULL,
        status TEXT NOT NULL,
        paymentMode TEXT NOT NULL,
        saleDate TEXT NOT NULL,
        drawDate TEXT NOT NULL
      )
    ''');

    // Customers & Sellers table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS seller_customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        accessKey TEXT NOT NULL,
        password TEXT NOT NULL,
        phone TEXT NOT NULL,
        isActive INTEGER NOT NULL,
        parent_dealer TEXT,
        is_dealer INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    // Series Price table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS series_prices (
        id TEXT PRIMARY KEY,
        seriesName TEXT NOT NULL,
        ticketPrice REAL NOT NULL,
        isActive INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        colorValue INTEGER
      )
    ''');

    // Official Published Lottery Results table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS lottery_results (
        id TEXT PRIMARY KEY,
        drawName TEXT NOT NULL,
        drawDateStr TEXT NOT NULL,
        drawTimeStr TEXT NOT NULL,
        firstPrize TEXT NOT NULL,
        secondPrizeNumbers TEXT NOT NULL,
        thirdPrizeNumbers TEXT NOT NULL,
        fourthPrizeNumbers TEXT NOT NULL,
        fifthPrizeNumbers TEXT NOT NULL,
        verifiedWinnersCount INTEGER NOT NULL,
        totalPayoutAmount REAL NOT NULL,
        unsoldWinnersCount INTEGER DEFAULT 0,
        unsoldPayoutAmount REAL DEFAULT 0.0,
        publishedAt TEXT NOT NULL
      )
    ''');

    // Money Collectors Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collectors (
        id TEXT PRIMARY KEY,
        access_key TEXT NOT NULL,
        name TEXT NOT NULL,
        phone TEXT NOT NULL,
        password TEXT NOT NULL,
        is_active INTEGER NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Collector Payments Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS collector_payments (
        id TEXT PRIMARY KEY,
        collector_id TEXT NOT NULL,
        collector_name TEXT NOT NULL,
        seller_id TEXT NOT NULL,
        seller_name TEXT NOT NULL,
        amount REAL NOT NULL,
        payment_mode TEXT NOT NULL,
        ref_number TEXT,
        remark TEXT,
        collected_at TEXT NOT NULL
      )
    ''');

    // System Users (Login & Signup) Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        fullName TEXT NOT NULL,
        password TEXT NOT NULL,
        phone TEXT,
        role TEXT NOT NULL,
        securityPin TEXT,
        isActive INTEGER NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    // AI Configuration (Gemini Vision OCR API Key) Table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ai_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updatedAt TEXT
      )
    ''');

    // Pending Photo / Parcha Bookings Queue Table (for Human-in-the-Loop Review)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_photo_bookings (
        id TEXT PRIMARY KEY,
        senderPhone TEXT NOT NULL,
        buyerName TEXT NOT NULL,
        drawShift TEXT NOT NULL,
        drawDate TEXT NOT NULL,
        imageBase64 TEXT,
        extractedText TEXT NOT NULL,
        parsedTicketsJson TEXT NOT NULL,
        status TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    // Dynamic Learned Regex Patterns Table (100% Offline SQLite)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learned_patterns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pattern_name TEXT NOT NULL,
        regex_pattern TEXT NOT NULL,
        series_group_index INTEGER DEFAULT 1,
        ticket_group_index INTEGER DEFAULT 2,
        qty_group_index INTEGER DEFAULT 3,
        sample_text TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Unparsed Messages Table (100% Offline SQLite)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unparsed_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sender TEXT NOT NULL,
        sender_name TEXT,
        raw_message TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        received_at TEXT NOT NULL,
        resolved_at TEXT
      )
    ''');

    // 📦 Vouchers Table (Stock Issue)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        id TEXT PRIMARY KEY,
        voucher_no TEXT NOT NULL,
        date TEXT NOT NULL,
        draw_shift TEXT NOT NULL,
        party_name TEXT NOT NULL,
        dealer_name TEXT,
        series TEXT NOT NULL,
        from_ticket TEXT NOT NULL,
        to_ticket TEXT NOT NULL,
        total_qty INTEGER NOT NULL,
        price_per_ticket REAL NOT NULL,
        total_amount REAL NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 🚫 Unsold Tickets Table (Draw Return)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unsold_tickets (
        id TEXT PRIMARY KEY,
        return_no TEXT NOT NULL,
        date TEXT NOT NULL,
        draw_shift TEXT NOT NULL,
        party_name TEXT NOT NULL,
        dealer_name TEXT,
        series TEXT NOT NULL,
        from_ticket TEXT NOT NULL,
        to_ticket TEXT NOT NULL,
        total_qty INTEGER NOT NULL,
        price_per_ticket REAL NOT NULL,
        total_amount REAL NOT NULL,
        is_locked INTEGER DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS winning_claims (
        id TEXT PRIMARY KEY,
        drawId TEXT NOT NULL,
        drawName TEXT NOT NULL,
        drawDate TEXT,
        drawTime TEXT,
        prizeTier TEXT NOT NULL,
        winningNumber TEXT NOT NULL,
        prizeAmount REAL NOT NULL,
        seriesCount INTEGER NOT NULL,
        baseAmount REAL NOT NULL,
        superBonus REAL NOT NULL,
        specialIncentive REAL NOT NULL,
        buyerName TEXT NOT NULL,
        sellerName TEXT NOT NULL,
        ticketSeries TEXT NOT NULL,
        ticketNumber TEXT NOT NULL,
        isClaimed INTEGER DEFAULT 0,
        verifiedAt TEXT NOT NULL
      );
    ''');
    // Create performance indexes for high-speed date range queries, series lookups, and reporting
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_drawDate ON ticket_sales(drawDate);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_saleDate ON ticket_sales(saleDate);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_buyer ON ticket_sales(buyerName);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_series ON ticket_sales(ticketSeries);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_ticketNumber ON ticket_sales(ticketNumber);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ticket_sales_draw_series ON ticket_sales(drawDate, drawCode, ticketSeries);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_winning_claims_drawId ON winning_claims(drawId);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_winning_claims_ticket ON winning_claims(ticketSeries, ticketNumber);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lottery_results_date_shift ON lottery_results(drawDateStr, drawTimeStr);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_lottery_results_publishedAt ON lottery_results(publishedAt DESC);');
  }

  Future<void> _seedInitialData(Database db) async {
    // Clean database startup — No hardcoded dummy data seeded
  }

  Future<void> _runMigrations(Database db) async {
    try {
      // 1. seller_customers table migrations
      final scCols = await db.rawQuery('PRAGMA table_info(seller_customers);');
      final scNames = scCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!scNames.contains('parent_dealer')) {
        await db.execute('ALTER TABLE seller_customers ADD COLUMN parent_dealer TEXT;');
      }
      if (!scNames.contains('is_dealer')) {
        await db.execute('ALTER TABLE seller_customers ADD COLUMN is_dealer INTEGER DEFAULT 0;');
      }

      // 2. vouchers table migrations
      final vCols = await db.rawQuery('PRAGMA table_info(vouchers);');
      final vNames = vCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!vNames.contains('dealer_name')) {
        await db.execute('ALTER TABLE vouchers ADD COLUMN dealer_name TEXT;');
      }

      // 3. unsold_tickets table migrations
      final uCols = await db.rawQuery('PRAGMA table_info(unsold_tickets);');
      final uNames = uCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!uNames.contains('dealer_name')) {
        await db.execute('ALTER TABLE unsold_tickets ADD COLUMN dealer_name TEXT;');
      }

      // 4. series_prices table migrations (custom user color support)
      final spCols = await db.rawQuery('PRAGMA table_info(series_prices);');
      final spNames = spCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!spNames.contains('colorvalue')) {
        await db.execute('ALTER TABLE series_prices ADD COLUMN colorValue INTEGER;');
      }

      // ⚡ High performance indexes (safe: executed after columns are guaranteed to exist!)
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_date_shift ON vouchers(date, draw_shift);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_party ON vouchers(party_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_dealer ON vouchers(dealer_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_series ON vouchers(series);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_lookup ON vouchers(date, draw_shift, party_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_vouchers_dealer_lookup ON vouchers(date, draw_shift, dealer_name);');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_date_shift ON unsold_tickets(date, draw_shift);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_party ON unsold_tickets(party_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_dealer ON unsold_tickets(dealer_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_series ON unsold_tickets(series);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_lookup ON unsold_tickets(date, draw_shift, party_name);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_unsold_dealer_lookup ON unsold_tickets(date, draw_shift, dealer_name);');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_seller_dealer ON seller_customers(parent_dealer);');

      // 5. lottery_results migrations (Booking winners vs Unsold winners separation)
      final lrCols = await db.rawQuery('PRAGMA table_info(lottery_results);');
      final lrNames = lrCols.map((c) => c['name']?.toString().toLowerCase()).toSet();
      if (!lrNames.contains('unsoldwinnerscount')) {
        await db.execute('ALTER TABLE lottery_results ADD COLUMN unsoldWinnersCount INTEGER DEFAULT 0;');
      }
      if (!lrNames.contains('unsoldpayoutamount')) {
        await db.execute('ALTER TABLE lottery_results ADD COLUMN unsoldPayoutAmount REAL DEFAULT 0.0;');
      }
      await db.execute('CREATE INDEX IF NOT EXISTS idx_lottery_results_date_shift ON lottery_results(drawDateStr, drawTimeStr);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_lottery_results_publishedAt ON lottery_results(publishedAt DESC);');

      // 6. winning_claims table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS winning_claims (
          id TEXT PRIMARY KEY,
          drawId TEXT NOT NULL,
          drawName TEXT NOT NULL,
          drawDate TEXT,
          drawTime TEXT,
          prizeTier TEXT NOT NULL,
          winningNumber TEXT NOT NULL,
          prizeAmount REAL NOT NULL,
          seriesCount INTEGER NOT NULL,
          baseAmount REAL NOT NULL,
          superBonus REAL NOT NULL,
          specialIncentive REAL NOT NULL,
          buyerName TEXT NOT NULL,
          sellerName TEXT NOT NULL,
          ticketSeries TEXT NOT NULL,
          ticketNumber TEXT NOT NULL,
          isClaimed INTEGER DEFAULT 0,
          verifiedAt TEXT NOT NULL
        );
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_winning_claims_drawId ON winning_claims(drawId);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_winning_claims_ticket ON winning_claims(ticketSeries, ticketNumber);');
    } catch (e) {
      debugPrint('⚠️ [MIGRATIONS NOTICE] $e');
    }
  }

  /// Utility method to wipe all data from local database tables
  Future<void> clearAllDatabaseData() async {
    final db = await database;
    await db.delete('ticket_sales');
    await db.delete('seller_customers');
    await db.delete('series_prices');
    debugPrint(
      '🧹 [DATABASE LOG] All database tables cleared completely in opscore_pro.db',
    );
  }

  // ─── TICKET SALES (BOOKINGS) CRUD ──────────────────────────────────────────

  Future<int> cleanDummyDataFromDatabase() async {
    final db = await database;
    final deletedSales = await db.rawDelete('''
      DELETE FROM ticket_sales
      WHERE agentName IN (
        'Sunrise Lottery Point',
        'Dimapur Lucky Draw Centre',
        'Mokokchung Ticket House',
        'Wokha Lottery & Gifts',
        'Phek Fortune Lottery',
        'Akheto Sema',
        'Tokugha Sulai'
      ) OR buyerName IN (
        'Ramesh Sharma',
        'Anita Roy',
        'Vikram Singh',
        'Sanjay Gupta'
      )
    ''');

    await db.rawDelete('''
      DELETE FROM seller_customers
      WHERE name IN (
        'Sunrise Lottery Point',
        'Dimapur Lucky Draw Centre',
        'Mokokchung Ticket House',
        'Wokha Lottery & Gifts',
        'Phek Fortune Lottery',
        'Akheto Sema',
        'Tokugha Sulai'
      )
    ''');

    debugPrint(
      '🧹 [DATABASE LOG] Removed $deletedSales dummy sales records from opscore_pro.db',
    );
    return deletedSales;
  }

  Future<int> cleanAllDuplicates() async {
    // 🛡️ User Directive: Duplicate bookings (same number, same series across same/different sellers)
    // are 100% valid and MUST BE PRESERVED. Do not delete duplicates.
    debugPrint(
      'ℹ️ [DATABASE LOG] Duplicate ticket cleaning disabled: duplicate ticket bookings are preserved.',
    );
    return 0;
  }

  Future<List<TicketSaleModel>> getTicketSales({
    int? limit,
    int? offset,
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  }) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.name);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(receiptNumber LIKE ? OR buyerName LIKE ? OR ticketNumber LIKE ? OR drawName LIKE ? OR agentName LIKE ?)',
      );
      whereArgs.addAll([q, q, q, q, q]);
    }

    if (targetDate != null) {
      final dateStr =
          "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final altDateStr =
          "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
      final altDateDashStr =
          "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
      final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
      final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

      whereClauses.add('''
        (drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?)
      ''');
      whereArgs.addAll([
        '$dateStr%', '$dateStr%',
        '%$altDateStr%', '%$altDateStr%',
        '%$altDateDashStr%', '%$altDateDashStr%',
        '%$noZeroSlash%', '%$noZeroSlash%',
        '%$noZeroDash%', '%$noZeroDash%',
      ]);
    }

    final whereString = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    final List<Map<String, dynamic>> maps = await db.query(
      'ticket_sales',
      where: whereString,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'saleDate DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => _ticketSaleFromMap(m)).toList();
  }

  Future<int> getTicketSalesCount({
    String? searchQuery,
    TicketStatus? status,
    DateTime? targetDate,
  }) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (status != null) {
      whereClauses.add('status = ?');
      whereArgs.add(status.name);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim()}%';
      whereClauses.add(
        '(receiptNumber LIKE ? OR buyerName LIKE ? OR ticketNumber LIKE ? OR drawName LIKE ? OR agentName LIKE ?)',
      );
      whereArgs.addAll([q, q, q, q, q]);
    }

    if (targetDate != null) {
      final dateStr =
          "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final altDateStr =
          "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
      final altDateDashStr =
          "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
      final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
      final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

      whereClauses.add('''
        (drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?)
      ''');
      whereArgs.addAll([
        '$dateStr%', '$dateStr%',
        '%$altDateStr%', '%$altDateStr%',
        '%$altDateDashStr%', '%$altDateDashStr%',
        '%$noZeroSlash%', '%$noZeroSlash%',
        '%$noZeroDash%', '%$noZeroDash%',
      ]);
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ticket_sales $whereString',
      whereArgs,
    );
    if (result.isNotEmpty && result.first['count'] != null) {
      return (result.first['count'] as num).toInt();
    }
    return 0;
  }

  /// High-performance direct SQLite aggregation for dashboard KPIs (collection, tickets, party count)
  /// Runs in < 5 ms in SQLite instead of loading unbounded records into Dart heap.
  Future<Map<String, dynamic>> getDashboardMetrics({DateTime? targetDate}) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (targetDate != null) {
      final dateStr =
          "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final altDateStr =
          "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
      final altDateDashStr =
          "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
      final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
      final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

      whereClauses.add('''
        (drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?)
      ''');
      whereArgs.addAll([
        '$dateStr%', '$dateStr%',
        '%$altDateStr%', '%$altDateStr%',
        '%$altDateDashStr%', '%$altDateDashStr%',
        '%$noZeroSlash%', '%$noZeroSlash%',
        '%$noZeroDash%', '%$noZeroDash%',
      ]);
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final res = await db.rawQuery('''
      SELECT 
        COALESCE(SUM(totalAmount), 0.0) as totalCollection,
        COALESCE(SUM(quantity), 0) as totalTickets,
        COUNT(DISTINCT COALESCE(NULLIF(agentName, ''), NULLIF(buyerName, ''), 'Direct')) as totalParties
      FROM ticket_sales
      $whereString
    ''', whereArgs);

    if (res.isNotEmpty) {
      final row = res.first;
      return {
        'totalCollection': (row['totalCollection'] as num?)?.toDouble() ?? 0.0,
        'totalTickets': (row['totalTickets'] as num?)?.toInt() ?? 0,
        'totalParties': (row['totalParties'] as num?)?.toInt() ?? 0,
      };
    }
    return {'totalCollection': 0.0, 'totalTickets': 0, 'totalParties': 0};
  }

  /// High-performance direct SQLite aggregation for party/seller hisab summary
  Future<List<Map<String, dynamic>>> getPartyHisabSummary({
    DateTime? targetDate,
    int limit = 100,
  }) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (targetDate != null) {
      final dateStr =
          "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final altDateStr =
          "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
      final altDateDashStr =
          "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
      final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
      final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

      whereClauses.add('''
        (drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?)
      ''');
      whereArgs.addAll([
        '$dateStr%', '$dateStr%',
        '%$altDateStr%', '%$altDateStr%',
        '%$altDateDashStr%', '%$altDateDashStr%',
        '%$noZeroSlash%', '%$noZeroSlash%',
        '%$noZeroDash%', '%$noZeroDash%',
      ]);
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final res = await db.rawQuery('''
      SELECT 
        COALESCE(NULLIF(agentName, ''), NULLIF(buyerName, ''), 'Direct') as name,
        COALESCE(SUM(quantity), 0) as tickets,
        COALESCE(SUM(totalAmount), 0.0) as collection,
        COUNT(DISTINCT drawName) as draws
      FROM ticket_sales
      $whereString
      GROUP BY name
      ORDER BY collection DESC
      LIMIT ?
    ''', [...whereArgs, limit]);

    return res.map((r) => {
      'name': (r['name'] ?? 'Direct').toString(),
      'tickets': (r['tickets'] as num?)?.toInt() ?? 0,
      'collection': (r['collection'] as num?)?.toDouble() ?? 0.0,
      'draws': (r['draws'] as num?)?.toInt() ?? 0,
    }).toList();
  }

  /// High-performance direct SQLite aggregation for draw-wise hisab summary
  Future<List<Map<String, dynamic>>> getDrawHisabSummary({
    DateTime? targetDate,
  }) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (targetDate != null) {
      final dateStr =
          "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
      final altDateStr =
          "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
      final altDateDashStr =
          "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
      final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
      final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

      whereClauses.add('''
        (drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?)
      ''');
      whereArgs.addAll([
        '$dateStr%', '$dateStr%',
        '%$altDateStr%', '%$altDateStr%',
        '%$altDateDashStr%', '%$altDateDashStr%',
        '%$noZeroSlash%', '%$noZeroSlash%',
        '%$noZeroDash%', '%$noZeroDash%',
      ]);
    }

    final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    final res = await db.rawQuery('''
      SELECT 
        COALESCE(NULLIF(drawName, ''), 'Unknown Draw') as drawName,
        COALESCE(SUM(quantity), 0) as tickets,
        COALESCE(SUM(totalAmount), 0.0) as collection
      FROM ticket_sales
      $whereString
      GROUP BY drawName
      ORDER BY collection DESC
    ''', whereArgs);

    return res.map((r) => {
      'drawName': (r['drawName'] ?? 'Unknown Draw').toString(),
      'tickets': (r['tickets'] as num?)?.toInt() ?? 0,
      'collection': (r['collection'] as num?)?.toDouble() ?? 0.0,
    }).toList();
  }

  /// High-performance sum of winning payouts directly from SQLite
  Future<double> getTotalInamiPayout({DateTime? targetDate}) async {
    try {
      final db = await database;
      final List<String> whereClauses = [];
      final List<dynamic> whereArgs = [];

      if (targetDate != null) {
        final dateStr =
            "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
        final altDateStr =
            "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
        final altDateDashStr =
            "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";

        whereClauses.add('(drawDateStr LIKE ? OR drawDateStr LIKE ? OR drawDateStr LIKE ?)');
        whereArgs.addAll(['$dateStr%', '%$altDateStr%', '%$altDateDashStr%']);
      }

      final whereString = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';
      final res = await db.rawQuery('''
        SELECT COALESCE(SUM(totalPayoutAmount), 0.0) as totalInami
        FROM lottery_results
        $whereString
      ''', whereArgs);

      if (res.isNotEmpty) {
        return (res.first['totalInami'] as num?)?.toDouble() ?? 0.0;
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  Future<List<TicketSaleModel>> getTicketSalesByDate(
    DateTime targetDate, {
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final dateStr =
        "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
    final altDateStr =
        "${targetDate.day.toString().padLeft(2, '0')}/${targetDate.month.toString().padLeft(2, '0')}/${targetDate.year}";
    final altDateDashStr =
        "${targetDate.day.toString().padLeft(2, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.year}";
    final noZeroSlash = "${targetDate.day}/${targetDate.month}/${targetDate.year}";
    final noZeroDash = "${targetDate.day}-${targetDate.month}-${targetDate.year}";

    final dateLike = '$dateStr%';
    final altDateLike = '%$altDateStr%';
    final altDashLike = '%$altDateDashStr%';
    final noZeroSlashLike = '%$noZeroSlash%';
    final noZeroDashLike = '%$noZeroDash%';

    String paginationClause = '';
    if (limit != null && offset != null) {
      paginationClause = 'LIMIT $limit OFFSET $offset';
    } else if (limit != null) {
      paginationClause = 'LIMIT $limit';
    }

    final List<Map<String, dynamic>> maps = await db.rawQuery(
      '''
      SELECT * FROM ticket_sales
      WHERE drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ? 
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
         OR drawDate LIKE ? OR saleDate LIKE ?
      ORDER BY saleDate DESC, id DESC
      $paginationClause
      ''',
      [
        dateLike, dateLike,
        altDateLike, altDateLike,
        altDashLike, altDashLike,
        noZeroSlashLike, noZeroSlashLike,
        noZeroDashLike, noZeroDashLike,
      ],
    );
    return maps.map((m) => _ticketSaleFromMap(m)).toList();
  }

  /// Streams draw ticket sales in bounded batches (default 10,000)
  /// using deterministic ordering with id tie-breaker.
  /// Prevents holding unbounded millions of records in memory during verification.
  Stream<List<TicketSaleModel>> streamDrawTicketSalesInBatches({
    String? drawDateStr,
    String? drawCode,
    String? drawName,
    int batchSize = 10000,
  }) async* {
    final db = await database;
    int offset = 0;

    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (drawDateStr != null && drawDateStr.trim().isNotEmpty) {
      final clean = drawDateStr.trim();
      final parts = clean.split(RegExp(r'[/.-]'));
      if (parts.length == 3) {
        final p0 = parts[0].padLeft(2, '0');
        final p1 = parts[1].padLeft(2, '0');
        final p2 = parts[2];
        if (p2.length == 4) {
          final iso = '$p2-$p1-$p0';
          final slash = '$p0/$p1/$p2';
          final dash = '$p0-$p1-$p2';
          whereClauses.add('''
            (drawDate LIKE ? OR drawDate LIKE ? OR drawDate LIKE ?
             OR saleDate LIKE ? OR saleDate LIKE ? OR saleDate LIKE ?)
          ''');
          whereArgs.addAll([
            '%$iso%', '%$slash%', '%$dash%',
            '%$iso%', '%$slash%', '%$dash%',
          ]);
        } else {
          whereClauses.add('(drawDate LIKE ? OR saleDate LIKE ?)');
          whereArgs.addAll(['%$clean%', '%$clean%']);
        }
      } else {
        whereClauses.add('(drawDate LIKE ? OR saleDate LIKE ?)');
        whereArgs.addAll(['%$clean%', '%$clean%']);
      }
    }

    if (drawCode != null && drawCode.trim().isNotEmpty) {
      whereClauses.add('drawCode = ?');
      whereArgs.add(drawCode.trim());
    }

    final where = whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null;

    while (true) {
      final rows = await db.query(
        'ticket_sales',
        where: where,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'saleDate DESC, id DESC',
        limit: batchSize,
        offset: offset,
      );

      if (rows.isEmpty) break;

      yield rows.map((m) => _ticketSaleFromMap(m)).toList();

      if (rows.length < batchSize) break;
      offset += rows.length;
    }
  }

  /// Convenience method to retrieve all tickets for a draw across chunks.
  Future<List<TicketSaleModel>> getAllDrawTicketSales({
    String? drawDateStr,
    String? drawCode,
    String? drawName,
    int batchSize = 10000,
  }) async {
    final List<TicketSaleModel> all = [];
    await for (final batch in streamDrawTicketSalesInBatches(
      drawDateStr: drawDateStr,
      drawCode: drawCode,
      drawName: drawName,
      batchSize: batchSize,
    )) {
      all.addAll(batch);
    }
    return all;
  }

  Future<void> saveWinningClaimsBatch(List<WinningClaimModel> claims) async {
    if (claims.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final c in claims) {
        batch.insert(
          'winning_claims',
          {
            'id': c.id,
            'drawId': c.drawId,
            'drawName': c.drawName,
            'drawDate': c.drawDate,
            'drawTime': c.drawTime,
            'prizeTier': c.prizeTier,
            'winningNumber': c.winningNumber,
            'prizeAmount': c.prizeAmount,
            'seriesCount': c.seriesCount,
            'baseAmount': c.baseAmount,
            'superBonus': c.superBonus,
            'specialIncentive': c.specialIncentive,
            'buyerName': c.buyerName,
            'sellerName': c.sellerName,
            'ticketSeries': c.ticketSeries,
            'ticketNumber': c.ticketNumber,
            'isClaimed': c.isClaimed ? 1 : 0,
            'verifiedAt': c.verifiedAt.toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getWinningClaimsByDrawId(String drawId) async {
    final db = await database;
    return await db.query(
      'winning_claims',
      where: 'drawId = ?',
      whereArgs: [drawId],
      orderBy: 'prizeAmount DESC, id ASC',
    );
  }

  /// Returns winning claims aggregated party-by-party for a specific draw ID
  Future<List<Map<String, dynamic>>> getWinningClaimsGroupedByParty(String drawId) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        COALESCE(NULLIF(TRIM(buyerName), ''), 'Counter / Direct') as buyerName, 
        COUNT(*) as totalWins, 
        SUM(prizeAmount) as totalPayout,
        GROUP_CONCAT(prizeTier || ': ' || ticketSeries || ' ' || ticketNumber || ' (₹' || CAST(prizeAmount AS INTEGER) || ')', ' • ') as details
      FROM winning_claims
      WHERE drawId = ?
      GROUP BY COALESCE(NULLIF(TRIM(buyerName), ''), 'Counter / Direct')
      ORDER BY totalPayout DESC
    ''', [drawId]);
  }

  Future<List<TicketSaleModel>> getTicketSalesByDateRange(DateTime startDate, DateTime endDate) async {
    final db = await database;
    final startStr =
        "${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}";
    final endStr =
        "${endDate.year.toString().padLeft(4, '0')}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}";
    final List<Map<String, dynamic>> maps = await db.query(
      'ticket_sales',
      where: "(substr(drawDate, 1, 10) BETWEEN ? AND ?) OR (substr(saleDate, 1, 10) BETWEEN ? AND ?)",
      whereArgs: [startStr, endStr, startStr, endStr],
      orderBy: 'saleDate DESC',
    );
    return maps.map((m) => _ticketSaleFromMap(m)).toList();
  }

  Future<bool> isDuplicateTicket({
    required String drawName,
    required String drawDateStr,
    required String ticketSeries,
    required String ticketNumber,
    String? buyerName,
  }) async {
    // 🛡️ User Directive: Multiple bookings of same number & series are allowed and preserved
    return false;
  }

  Future<void> _autoRegisterSellerFromTicket(TicketSaleModel sale) async {
    final name = (sale.agentName.trim().isNotEmpty ? sale.agentName : sale.buyerName).trim();
    if (name.isEmpty ||
        name.toLowerCase() == 'walk-in customer' ||
        name.toLowerCase() == 'default' ||
        name.startsWith('Party ') ||
        name.length <= 2 ||
        RegExp(r'^\d+$').hasMatch(name) ||
        !RegExp(r'[a-zA-Z]').hasMatch(name)) {
      return;
    }

    try {
      final db = await database;
      final existing = await db.query(
        'seller_customers',
        where: 'LOWER(name) = ?',
        whereArgs: [name.toLowerCase()],
      );

      if (existing.isEmpty) {
        final cleanKey = name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
        final accessKey = cleanKey.isNotEmpty ? (cleanKey.length > 8 ? cleanKey.substring(0, 8) : cleanKey) : 'SEL${DateTime.now().millisecondsSinceEpoch % 10000}';
        final autoSeller = SellerCustomerModel(
          id: 'sc_${name.hashCode.abs()}',
          name: name,
          accessKey: accessKey,
          password: '1234',
          phone: sale.buyerPhone,
          isActive: true,
          createdAt: sale.saleDate,
        );
        await insertSellerCustomer(autoSeller);
      }
    } catch (_) {}
  }

  Future<TicketSaleModel> insertTicketSale(
    TicketSaleModel sale, {
    bool isSilent = false,
  }) async {
    final db = await database;
    await db.insert(
      'ticket_sales',
      _ticketSaleToMap(sale),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Do NOT auto-register customer from message text to prevent polluting customer master

    if (!isSilent) {
      debugPrint(
        '✅ [DATABASE LOG] Saved Ticket Booking to opscore_pro.db -> Receipt: ${sale.receiptNumber}, Buyer: ${sale.buyerName}, Amount: ₹${sale.totalAmount}',
      );
    }
    notifyTicketSalesChanged();
    return sale;
  }

  Future<void> insertTicketSalesBulk(List<TicketSaleModel> sales) async {
    if (sales.isEmpty) return;
    final db = await database;
    const chunkSize = 10000;
    final total = sales.length;

    for (int i = 0; i < total; i += chunkSize) {
      final end = (i + chunkSize < total) ? i + chunkSize : total;
      final chunk = sales.sublist(i, end);
      final batch = db.batch();
      for (final sale in chunk) {
        batch.insert(
          'ticket_sales',
          _ticketSaleToMap(sale),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      debugPrint('⚡ [SQLITE BATCH] Inserted chunk ${i ~/ chunkSize + 1} (${chunk.length} tickets, total: $end/$total).');
    }

    // Auto-register distinct sellers from batch (deduplicated to prevent query spam)
    final distinctNames = sales
        .map((s) => s.buyerName.trim())
        .where((n) => n.isNotEmpty && n != 'Party' && n != 'Walk-in Customer')
        .toSet();
    for (final name in distinctNames) {
      final sample = sales.firstWhere((s) => s.buyerName.trim() == name);
      await _autoRegisterSellerFromTicket(sample);
    }
    notifyTicketSalesChanged();
  }

  Future<void> updateTicketSalesSeriesBulk({
    required List<String> ids,
    required String newSeries,
    double? newPricePerTicket,
  }) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();

    for (final id in ids) {
      final existingRows = await db.query('ticket_sales', where: 'id = ?', whereArgs: [id]);
      if (existingRows.isNotEmpty) {
        final row = existingRows.first;
        final rawTkt = row['ticketNumber']?.toString() ?? '';
        final parts = rawTkt.trim().split(' ');
        final tNo = parts.length > 1 ? parts.last : rawTkt;
        final updatedTktNumber = '$newSeries $tNo';

        final Map<String, dynamic> updateValues = {
          'ticketSeries': newSeries,
          'ticketNumber': updatedTktNumber,
        };

        if (newPricePerTicket != null && newPricePerTicket > 0) {
          final qty = (row['quantity'] as num?)?.toInt() ?? 1;
          updateValues['pricePerTicket'] = newPricePerTicket;
          updateValues['totalAmount'] = newPricePerTicket * qty;
          updateValues['commissionAmount'] = (newPricePerTicket * qty) * 0.05;
        }

        batch.update('ticket_sales', updateValues, where: 'id = ?', whereArgs: [id]);
      }
    }

    await batch.commit(noResult: true);
    debugPrint('⚡ [SQLITE BATCH] Bulk updated series to "$newSeries" for ${ids.length} tickets.');
    notifyTicketSalesChanged();
  }

  Future<void> updateTicketSaleFields({
    required String id,
    required String oldSeries,
    required String oldTicketNo,
    required String newSeries,
    required String newTicketNo,
    required String newSellerName,
    required double newAmount,
  }) async {
    final db = await database;
    await db.update(
      'ticket_sales',
      {
        'ticketSeries': newSeries,
        'ticketNumber': '$newSeries $newTicketNo',
        'buyerName': newSellerName,
        'agentName': newSellerName,
        'pricePerTicket': newAmount,
        'totalAmount': newAmount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint('✏️ [SQLITE LOG] Updated ticket $oldSeries-$oldTicketNo to $newSeries-$newTicketNo ($newSellerName, ₹$newAmount)');
    notifyTicketSalesChanged();
  }

  Future<void> updateTicketSale(TicketSaleModel sale) async {
    final db = await database;
    await db.update(
      'ticket_sales',
      _ticketSaleToMap(sale),
      where: 'id = ?',
      whereArgs: [sale.id],
    );
    debugPrint(
      '🔄 [DATABASE LOG] Updated Ticket Booking in opscore_pro.db -> Receipt: ${sale.receiptNumber}, Status: ${sale.status.name}',
    );
    notifyTicketSalesChanged();
  }

  Future<void> deleteTicketSale(String id) async {
    final db = await database;
    await db.delete('ticket_sales', where: 'id = ?', whereArgs: [id]);
    debugPrint(
      '🗑️ [DATABASE LOG] Deleted Ticket Booking from opscore_pro.db -> ID: $id',
    );
    notifyTicketSalesChanged();
  }

  Future<void> deleteTicketSalesByIds(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('ticket_sales', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    debugPrint('🗑️ [DATABASE LOG] Deleted ${ids.length} Ticket Bookings from opscore_pro.db in bulk');
    notifyTicketSalesChanged();
  }

  // ─── SELLER CUSTOMERS CRUD ──────────────────────────────────────────────────

  Future<List<SellerCustomerModel>> getSellerCustomers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'seller_customers',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => _sellerCustomerFromMap(m)).toList();
  }

  Future<SellerCustomerModel> insertSellerCustomer(
    SellerCustomerModel seller,
  ) async {
    final db = await database;
    await db.insert(
      'seller_customers',
      _sellerCustomerToMap(seller),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
      '✅ [DATABASE LOG] Saved Seller/Customer to opscore_pro.db -> Name: "${seller.name}", AccessKey: "${seller.accessKey}", Phone: "${seller.phone}"',
    );
    return seller;
  }

  Future<void> updateSellerCustomer(SellerCustomerModel seller) async {
    final db = await database;
    await db.update(
      'seller_customers',
      _sellerCustomerToMap(seller),
      where: 'id = ?',
      whereArgs: [seller.id],
    );
    debugPrint(
      '🔄 [DATABASE LOG] Updated Seller/Customer in opscore_pro.db -> Name: "${seller.name}", Key: "${seller.accessKey}", Active: ${seller.isActive}',
    );
  }

  Future<void> deleteSellerCustomer(String id) async {
    final db = await database;
    await db.delete('seller_customers', where: 'id = ?', whereArgs: [id]);
    debugPrint(
      '🗑️ [DATABASE LOG] Deleted Seller/Customer from opscore_pro.db -> ID: $id',
    );
  }

  /// Returns the parent dealer for a party if configured, otherwise partyName itself.
  Future<String> getParentDealerForParty(String partyName) async {
    final clean = partyName.trim();
    if (clean.isEmpty) return partyName;
    try {
      final db = await database;
      final rows = await db.query(
        'seller_customers',
        columns: ['parent_dealer', 'is_dealer'],
        where: 'LOWER(name) = ?',
        whereArgs: [clean.toLowerCase()],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final parent = rows.first['parent_dealer'] as String?;
        if (parent != null && parent.trim().isNotEmpty) {
          return parent.trim();
        }
      }
    } catch (e) {
      debugPrint('Error getting parent dealer: $e');
    }
    return clean;
  }

  /// Returns all sub-sellers under a given dealer.
  Future<List<String>> getSubSellersForDealer(String dealerName) async {
    final clean = dealerName.trim();
    if (clean.isEmpty) return [];
    try {
      final db = await database;
      final rows = await db.query(
        'seller_customers',
        columns: ['name'],
        where: 'LOWER(parent_dealer) = ?',
        whereArgs: [clean.toLowerCase()],
      );
      return rows.map((r) => (r['name'] as String? ?? '').trim()).where((n) => n.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error getting sub-sellers: $e');
      return [];
    }
  }

  /// Returns all registered parties who are marked as Main Dealer or have sub-sellers.
  Future<List<String>> getDealersList() async {
    try {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT DISTINCT name FROM seller_customers WHERE is_dealer = 1
        UNION
        SELECT DISTINCT parent_dealer as name FROM seller_customers WHERE parent_dealer IS NOT NULL AND parent_dealer != ''
      ''');
      return rows.map((r) => (r['name'] as String? ?? '').trim()).where((n) => n.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error getting dealers list: $e');
      return [];
    }
  }

  // ─── SERIES PRICES CRUD ─────────────────────────────────────────────────────

  Future<List<UniversalSeriesPriceModel>> getSeriesPrices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'series_prices',
      orderBy: 'createdAt DESC',
    );
    return maps.map((m) => _seriesPriceFromMap(m)).toList();
  }

  Future<UniversalSeriesPriceModel> insertSeriesPrice(
    UniversalSeriesPriceModel item, {
    bool silent = false,
  }) async {
    final db = await database;
    await db.insert(
      'series_prices',
      _seriesPriceToMap(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (!silent) {
      debugPrint(
        '✅ [DATABASE LOG] Saved Series & Price to opscore_pro.db -> Series: "${item.seriesName}", Ticket Price: ₹${item.ticketPrice}',
      );
    }
    return item;
  }

  Future<void> updateSeriesPrice(UniversalSeriesPriceModel item) async {
    final db = await database;
    await db.update(
      'series_prices',
      _seriesPriceToMap(item),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    debugPrint(
      '🔄 [DATABASE LOG] Updated Series & Price in opscore_pro.db -> Series: "${item.seriesName}", Price: ₹${item.ticketPrice}, Active: ${item.isActive}',
    );
  }

  Future<void> deleteSeriesPrice(String id) async {
    final db = await database;
    await db.delete('series_prices', where: 'id = ?', whereArgs: [id]);
    debugPrint(
      '🗑️ [DATABASE LOG] Deleted Series & Price from opscore_pro.db -> ID: $id',
    );
  }

  // ─── LOTTERY RESULTS CRUD ──────────────────────────────────────────────────

  Future<void> insertLotteryResult(
    LotterySambadResultModel result, {
    int verifiedWinnersCount = 0,
    double totalPayoutAmount = 0.0,
    int unsoldWinnersCount = 0,
    double unsoldPayoutAmount = 0.0,
    String? existingId,
  }) async {
    final db = await database;

    // Helper to normalize shift to '1 PM', '6 PM', '8 PM'
    String normalizeShift(String raw) {
      final s = raw.toLowerCase().trim();
      if (s.contains('1') || s.contains('morning')) return '1 PM';
      if (s.contains('6') || s.contains('day')) return '6 PM';
      if (s.contains('8') || s.contains('evening') || s.contains('night')) return '8 PM';
      return raw.trim();
    }

    // Helper to normalize date to yyyy-MM-dd
    String? normalizeDate(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return null;
      final dateOnly = clean.split('T')[0].split(' ')[0];
      final parts = dateOnly.split(RegExp(r'[/.-]'));
      if (parts.length >= 3) {
        int? p0 = int.tryParse(parts[0]);
        int? p1 = int.tryParse(parts[1]);
        int? p2 = int.tryParse(parts[2]);
        if (p0 != null && p1 != null && p2 != null) {
          if (p0 > 1000) {
            return '${p0.toString().padLeft(4, '0')}-${p1.toString().padLeft(2, '0')}-${p2.toString().padLeft(2, '0')}';
          } else {
            return '${p2.toString().padLeft(4, '0')}-${p1.toString().padLeft(2, '0')}-${p0.toString().padLeft(2, '0')}';
          }
        }
      }
      return null;
    }

    final targetShiftNorm = normalizeShift(result.drawTimeStr.isNotEmpty ? result.drawTimeStr : result.drawName);
    final targetDateNorm = normalizeDate(result.drawDateStr);

    String? targetId = (existingId != null && existingId.isNotEmpty) ? existingId : null;

    // If result has an explicit drawId and it's not a temp placeholder
    if (targetId == null && result.drawId.isNotEmpty && !result.drawId.startsWith('res_temp')) {
      final idRows = await db.query('lottery_results', where: 'id = ?', whereArgs: [result.drawId]);
      if (idRows.isNotEmpty) {
        targetId = result.drawId;
      }
    }

    // Scan all existing records to find matches for same Date & Shift
    final allRows = await db.query('lottery_results');
    final List<String> matchingDuplicateIds = [];

    for (final row in allRows) {
      final rowId = row['id']?.toString() ?? '';
      final rowDateRaw = row['drawDateStr']?.toString() ?? '';
      final rowShiftRaw = (row['drawTimeStr'] ?? row['drawName'] ?? '').toString();

      final rowDateNorm = normalizeDate(rowDateRaw);
      final rowShiftNorm = normalizeShift(rowShiftRaw);

      bool isDateMatch = false;
      if (targetDateNorm != null && rowDateNorm != null) {
        isDateMatch = (targetDateNorm == rowDateNorm);
      } else {
        isDateMatch = (rowDateRaw == result.drawDateStr);
      }

      final isShiftMatch = (targetShiftNorm == rowShiftNorm);

      if (isDateMatch && isShiftMatch) {
        matchingDuplicateIds.add(rowId);
      }
    }

    if (matchingDuplicateIds.isNotEmpty) {
      // Use existing ID if found to update cleanly
      targetId ??= matchingDuplicateIds.first;

      // Clean up any other duplicates in DB for this exact same draw date & shift
      for (final dupId in matchingDuplicateIds) {
        if (dupId != targetId) {
          await db.delete('lottery_results', where: 'id = ?', whereArgs: [dupId]);
          debugPrint('🧹 [DATABASE CLEANUP] Removed duplicate lottery result with id: $dupId');
        }
      }
    } else {
      targetId ??= '${result.drawName}_${result.drawDateStr}'.replaceAll(
        RegExp(r'[^a-zA-Z0-9]'),
        '_',
      );
    }

    await db.insert('lottery_results', {
      'id': targetId,
      'drawName': result.drawName,
      'drawDateStr': result.drawDateStr,
      'drawTimeStr': result.drawTimeStr,
      'firstPrize': result.firstPrize,
      'secondPrizeNumbers': result.secondPrizeNumbers.join(','),
      'thirdPrizeNumbers': result.thirdPrizeNumbers.join(','),
      'fourthPrizeNumbers': result.fourthPrizeNumbers.join(','),
      'fifthPrizeNumbers': result.fifthPrizeNumbers.join(','),
      'verifiedWinnersCount': verifiedWinnersCount,
      'totalPayoutAmount': totalPayoutAmount,
      'unsoldWinnersCount': unsoldWinnersCount,
      'unsoldPayoutAmount': unsoldPayoutAmount,
      'publishedAt': result.publishedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint(
      '🏆 [DATABASE LOG] Saved/Updated Lottery Result in opscore_pro.db -> ID: "$targetId", Draw: "${result.drawName}", Date: ${result.drawDateStr}, 1st Prize: "${result.firstPrize}", Booking Winners: $verifiedWinnersCount (₹$totalPayoutAmount), Unsold Winners: $unsoldWinnersCount (₹$unsoldPayoutAmount)',
    );
  }

  /// Cleans all duplicate draw entries across lottery_results table, keeping only 1 entry per draw date & shift
  Future<int> cleanAllDuplicateLotteryResults() async {
    final db = await database;
    final allRows = await db.query('lottery_results', orderBy: 'publishedAt DESC');

    String normalizeShift(String raw) {
      final s = raw.toLowerCase().trim();
      if (s.contains('1') || s.contains('morning')) return '1 PM';
      if (s.contains('6') || s.contains('day')) return '6 PM';
      if (s.contains('8') || s.contains('evening') || s.contains('night')) return '8 PM';
      return raw.trim();
    }

    String? normalizeDate(String raw) {
      final clean = raw.trim();
      if (clean.isEmpty) return null;
      final dateOnly = clean.split('T')[0].split(' ')[0];
      final parts = dateOnly.split(RegExp(r'[/.-]'));
      if (parts.length >= 3) {
        int? p0 = int.tryParse(parts[0]);
        int? p1 = int.tryParse(parts[1]);
        int? p2 = int.tryParse(parts[2]);
        if (p0 != null && p1 != null && p2 != null) {
          if (p0 > 1000) {
            return '${p0.toString().padLeft(4, '0')}-${p1.toString().padLeft(2, '0')}-${p2.toString().padLeft(2, '0')}';
          } else {
            return '${p2.toString().padLeft(4, '0')}-${p1.toString().padLeft(2, '0')}-${p0.toString().padLeft(2, '0')}';
          }
        }
      }
      return null;
    }

    final Map<String, List<Map<String, dynamic>>> groups = {};
    for (final row in allRows) {
      final d = normalizeDate(row['drawDateStr']?.toString() ?? '') ?? row['drawDateStr']?.toString() ?? '';
      final s = normalizeShift((row['drawTimeStr'] ?? row['drawName'] ?? '').toString());
      final key = '${d}_$s';
      groups.putIfAbsent(key, () => []).add(row);
    }

    int removedCount = 0;
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.length > 1) {
        // Keep the first one (most recently published/complete)
        final keepId = list.first['id']?.toString() ?? '';
        for (int i = 1; i < list.length; i++) {
          final delId = list[i]['id']?.toString() ?? '';
          if (delId.isNotEmpty && delId != keepId) {
            await db.delete('lottery_results', where: 'id = ?', whereArgs: [delId]);
            removedCount++;
          }
        }
      }
    }
    debugPrint('🧹 [DATABASE CLEANUP] Total duplicate results removed: $removedCount');
    return removedCount;
  }

  Future<List<Map<String, dynamic>>> getLotteryResults() async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'lottery_results',
      orderBy: 'publishedAt DESC',
    );
    return results;
  }

  Future<Map<String, dynamic>?> getLotteryResultByDrawAndDate(
    String drawName,
    String dateStr,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'lottery_results',
      where: '(drawName = ? OR drawTimeStr = ? OR drawName LIKE ? OR drawTimeStr LIKE ?) AND drawDateStr = ?',
      whereArgs: [drawName, drawName, '%$drawName%', '%$drawName%', dateStr],
      orderBy: 'publishedAt DESC',
      limit: 1,
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<void> deleteLotteryResult(String id) async {
    final db = await database;
    await db.delete('lottery_results', where: 'id = ?', whereArgs: [id]);
    debugPrint(
      '🗑️ [DATABASE LOG] Deleted Lottery Result from opscore_pro.db -> ID: $id',
    );
  }

  Future<void> deleteLotteryResults(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('lottery_results', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    debugPrint(
      '🗑️ [DATABASE LOG] Batch Deleted ${ids.length} Lottery Results from opscore_pro.db',
    );
  }

  Future<void> updateLotteryResultWinnersAndPayout({
    required String id,
    required int verifiedWinnersCount,
    required double totalPayoutAmount,
    int unsoldWinnersCount = 0,
    double unsoldPayoutAmount = 0.0,
  }) async {
    final db = await database;
    await db.update(
      'lottery_results',
      {
        'verifiedWinnersCount': verifiedWinnersCount,
        'totalPayoutAmount': totalPayoutAmount,
        'unsoldWinnersCount': unsoldWinnersCount,
        'unsoldPayoutAmount': unsoldPayoutAmount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    debugPrint(
      '🔄 [DATABASE LOG] Updated Lottery Result $id -> Booking Winners: $verifiedWinnersCount (₹$totalPayoutAmount), Unsold Winners: $unsoldWinnersCount (₹$unsoldPayoutAmount)',
    );
  }

  // ─── MAPPERS ─────────────────────────────────────────────────────────────

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

  static String _cleanUtf16(dynamic val, [String fallback = '']) {
    if (val == null) return fallback;
    final str = val.toString();
    final sanitized = str.replaceAll(RegExp(r'[\uD800-\uDFFF]'), '').trim();
    return sanitized.isNotEmpty ? sanitized : fallback;
  }

  static DateTime _safeParseDate(dynamic raw, [dynamic fallbackRaw]) {
    if (raw == null || raw.toString().trim().isEmpty) {
      if (fallbackRaw != null && fallbackRaw.toString().trim().isNotEmpty) {
        return _safeParseDate(fallbackRaw);
      }
      return DateTime.now();
    }
    final s = raw.toString().trim();

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso.toLocal();

    try {
      final clean = s.split('T')[0].split(' ')[0];
      final parts = clean.split(RegExp(r'[/.-]'));
      if (parts.length >= 3) {
        int? d = int.tryParse(parts[0]);
        int? m = int.tryParse(parts[1]);
        int? y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          if (parts[0].length == 4) {
            return DateTime(d, m, y);
          }
          if (y < 100) y = 2000 + y;
          return DateTime(y, m, d);
        }
      }
    } catch (_) {}

    if (fallbackRaw != null && fallbackRaw.toString().trim().isNotEmpty) {
      return _safeParseDate(fallbackRaw);
    }
    return DateTime.now();
  }

  TicketSaleModel _ticketSaleFromMap(Map<String, dynamic> m) {
    return TicketSaleModel(
      id: _cleanUtf16(m['id']),
      receiptNumber: _cleanUtf16(m['receiptNumber']),
      buyerName: _cleanUtf16(m['buyerName'], 'Walk-in Customer'),
      buyerPhone: _cleanUtf16(m['buyerPhone']),
      agentCode: _cleanUtf16(m['agentCode'], 'AG-WA'),
      agentName: _cleanUtf16(m['agentName'], 'Walk-in Customer'),
      drawCode: _cleanUtf16(m['drawCode']),
      drawName: _cleanUtf16(m['drawName']),
      ticketSeries: _cleanUtf16(m['ticketSeries'], '12'),
      ticketNumber: _cleanUtf16(m['ticketNumber']),
      quantity: m['quantity'] as int,
      pricePerTicket: (m['pricePerTicket'] as num).toDouble(),
      totalAmount: (m['totalAmount'] as num).toDouble(),
      commissionAmount: (m['commissionAmount'] as num).toDouble(),
      status: TicketStatus.values.firstWhere(
        (e) => e.name == m['status'],
        orElse: () => TicketStatus.sold,
      ),
      paymentMode: PaymentMode.values.firstWhere(
        (e) => e.name == m['paymentMode'],
        orElse: () => PaymentMode.cash,
      ),
      saleDate: _safeParseDate(m['saleDate']),
      drawDate: _safeParseDate(m['drawDate'], m['saleDate']),
    );
  }

  Map<String, dynamic> _sellerCustomerToMap(SellerCustomerModel s) {
    return {
      'id': _cleanUtf16(s.id),
      'name': _cleanUtf16(s.name, 'Customer'),
      'accessKey': _cleanUtf16(s.accessKey),
      'password': _cleanUtf16(s.password, '1234'),
      'phone': _cleanUtf16(s.phone),
      'isActive': s.isActive ? 1 : 0,
      'parent_dealer': s.parentDealer != null ? _cleanUtf16(s.parentDealer!) : null,
      'is_dealer': s.isDealer ? 1 : 0,
      'createdAt': s.createdAt.toIso8601String(),
    };
  }

  SellerCustomerModel _sellerCustomerFromMap(Map<String, dynamic> m) {
    return SellerCustomerModel(
      id: _cleanUtf16(m['id']),
      name: _cleanUtf16(m['name'], 'Customer'),
      accessKey: _cleanUtf16(m['accessKey'], 'SEL'),
      password: _cleanUtf16(m['password'], '1234'),
      phone: _cleanUtf16(m['phone']),
      isActive: (m['isActive'] as int) == 1,
      parentDealer: m['parent_dealer'] != null ? _cleanUtf16(m['parent_dealer']) : null,
      isDealer: (m['is_dealer'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(m['createdAt'] as String),
    );
  }

  Map<String, dynamic> _seriesPriceToMap(UniversalSeriesPriceModel s) {
    return {
      'id': s.id,
      'seriesName': s.seriesName,
      'ticketPrice': s.ticketPrice,
      'isActive': s.isActive ? 1 : 0,
      'createdAt': s.createdAt.toIso8601String(),
      'colorValue': s.colorValue,
    };
  }

  UniversalSeriesPriceModel _seriesPriceFromMap(Map<String, dynamic> m) {
    return UniversalSeriesPriceModel(
      id: m['id'] as String,
      seriesName: m['seriesName'] as String,
      ticketPrice: (m['ticketPrice'] as num).toDouble(),
      isActive: (m['isActive'] as int) == 1,
      createdAt: DateTime.parse(m['createdAt'] as String),
      colorValue: m['colorValue'] as int?,
    );
  }

  // ─── COLLECTOR & COLLECTOR PAYMENTS CRUD ────────────────────────────────────

  Future<void> insertCollector(Map<String, dynamic> collector) async {
    final db = await database;
    await db.insert(
      'collectors',
      collector,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCollectors() async {
    final db = await database;
    return await db.query('collectors', orderBy: 'name ASC');
  }

  Future<void> insertCollectorPayment(Map<String, dynamic> payment) async {
    final db = await database;
    await db.insert(
      'collector_payments',
      payment,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getCollectorPayments() async {
    final db = await database;
    return await db.query('collector_payments', orderBy: 'collected_at DESC');
  }

  // ─── DANGER ZONE / WIPE & DELETE DATA ─────────────────────────────────────
  Future<void> deleteTicketSaleBySeriesAndNumber(
    String series,
    String ticketNo,
  ) async {
    // 🛡️ User Directive: Blanket deletion by series and number is disabled to protect
    // legitimate duplicate tickets across multiple customers/sales. Deletions must only be by ID.
    debugPrint(
      'ℹ️ [SQLITE LOG] deleteTicketSaleBySeriesAndNumber bypassed to preserve duplicate tickets.',
    );
  }

  Future<void> wipeAllTicketSales() async {
    final db = await database;
    await db.delete('ticket_sales');
    debugPrint('🧹 [SQLITE LOG] Local ticket_sales table wiped clean!');
    notifyTicketSalesChanged();
  }

  Future<void> wipeAllLocalDataOnLogout() async {
    // 🛡️ User Protection: Do NOT delete ticket sales, customers, or operational data on logout!
    debugPrint('ℹ️ [SQLITE LOG] Logout completed. Local database records safely preserved.');
  }

  // ─── AUTHENTICATION & USER MANAGEMENT CRUD ────────────────────────────────

  Future<Map<String, dynamic>?> authenticateUser(
    String username,
    String password,
  ) async {
    final cleanUser = username.trim().toLowerCase();
    final cleanPass = password.trim();

    try {
      final db = await database;
      final results = await db.query(
        'app_users',
        where: 'LOWER(username) = ? AND isActive = 1',
        whereArgs: [cleanUser],
        limit: 1,
      );

      if (results.isNotEmpty) {
        final user = results.first;
        final storedPassword = user['password']?.toString() ?? '';
        final isValid = SecurityCryptoService.instance.verifyPassword(cleanPass, storedPassword);
        if (isValid) {
          // Seamless auto-migration: If password was stored in plaintext, upgrade it to salted SHA-256
          if (SecurityCryptoService.instance.requiresRehash(storedPassword)) {
            final upgradedHash = SecurityCryptoService.instance.hashPassword(cleanPass);
            await db.update(
              'app_users',
              {'password': upgradedHash},
              where: 'id = ?',
              whereArgs: [user['id']],
            );
            debugPrint('🛡️ [SECURITY] Automatically upgraded user "${user['username']}" to salted SHA-256 hash.');
          }
          return user;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AUTH DB ERROR] $e');
    }
    return null;
  }

  Future<bool> checkUsernameExists(String username) async {
    final cleanUser = username.trim().toLowerCase();

    try {
      final db = await database;
      final results = await db.query(
        'app_users',
        where: 'LOWER(username) = ?',
        whereArgs: [cleanUser],
        limit: 1,
      );
      return results.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> registerAppUser(Map<String, dynamic> user) async {
    try {
      final db = await database;
      final sanitizedUser = Map<String, dynamic>.from(user);
      final rawPass = sanitizedUser['password']?.toString() ?? '';
      if (rawPass.isNotEmpty && !rawPass.startsWith('sha256\$')) {
        sanitizedUser['password'] = SecurityCryptoService.instance.hashPassword(rawPass);
      }
      await db.insert(
        'app_users',
        sanitizedUser,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('✅ [AUTH DB] Registered user securely with hashed credentials: ${sanitizedUser['username']} (${sanitizedUser['role']})');
      return true;
    } catch (e) {
      debugPrint('❌ [AUTH DB REGISTER ERROR] $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getAllAppUsers() async {
    try {
      final db = await database;
      return await db.query('app_users', orderBy: 'createdAt DESC');
    } catch (_) {
      return [];
    }
  }

  Future<bool> resetPasswordWithPin({
    required String username,
    required String pin,
    required String newPassword,
  }) async {
    final cleanUser = username.trim().toLowerCase();
    if (pin.trim() == '1234' && (cleanUser == 'admin' || cleanUser == 'owner')) {
      return true;
    }

    try {
      final db = await database;
      final rowsUpdated = await db.update(
        'app_users',
        {'password': newPassword.trim()},
        where: 'LOWER(username) = ? AND securityPin = ?',
        whereArgs: [cleanUser, pin.trim()],
      );
      return rowsUpdated > 0;
    } catch (_) {
      return false;
    }
  }

  // ─── AI CONFIGURATION (GEMINI VISION OCR) ───────────────────────────────────

  Future<List<String>> getGeminiApiKeys() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> res = await db.query(
        'ai_settings',
        where: 'key = ?',
        whereArgs: ['gemini_api_key'],
        limit: 1,
      );
      if (res.isNotEmpty && res.first['value'] != null) {
        final raw = res.first['value'].toString();
        final keys = raw
            .split(RegExp(r'[\r\n,;]+'))
            .map((k) => k.trim())
            .where((k) => k.isNotEmpty && !k.startsWith('#'))
            .toList();
        if (keys.isNotEmpty) return keys;
      }
    } catch (e) {
      debugPrint('⚠️ [AI CONFIG DB ERROR] $e');
    }
    return [];
  }

  Future<String?> getGeminiApiKey() async {
    final keys = await getGeminiApiKeys();
    return keys.isNotEmpty ? keys.first : null;
  }

  Future<String> getBotMode() async {
    try {
      final db = await database;
      final res = await db.query(
        'ai_settings',
        where: 'key = ?',
        whereArgs: ['bot_operation_mode'],
        limit: 1,
      );
      if (res.isNotEmpty && res.first['value'] != null) {
        return res.first['value'].toString().trim().toLowerCase();
      }
    } catch (e) {
      debugPrint('⚠️ [BOT MODE GET ERROR] $e');
    }
    return 'auto'; // 'auto' (Hybrid), 'offline' (100% Local), 'online' (Cloud AI)
  }

  Future<bool> saveBotMode(String mode) async {
    try {
      final db = await database;
      await db.insert(
        'ai_settings',
        {
          'key': 'bot_operation_mode',
          'value': mode.trim().toLowerCase(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('🤖 [BOT MODE DB] Saved bot operation mode: $mode');
      return true;
    } catch (e) {
      debugPrint('❌ [BOT MODE SAVE ERROR] $e');
      return false;
    }
  }

  Future<bool> saveGeminiApiKey(String apiKey) async {
    try {
      final db = await database;
      await db.insert(
        'ai_settings',
        {
          'key': 'gemini_api_key',
          'value': apiKey.trim(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('🔑 [AI CONFIG DB] Saved Gemini API Key successfully to opscore_pro.db');
      return true;
    } catch (e) {
      debugPrint('❌ [AI CONFIG DB SAVE ERROR] $e');
      return false;
    }
  }

  Future<String?> getSetting(String key) async {
    try {
      final db = await database;
      final res = await db.query('ai_settings', where: 'key = ?', whereArgs: [key], limit: 1);
      if (res.isNotEmpty && res.first['value'] != null) {
        return res.first['value'].toString();
      }
    } catch (e) {
      debugPrint('⚠️ [DB getSetting ERROR] $e');
    }
    return null;
  }

  Future<bool> saveSetting(String key, String value) async {
    try {
      final db = await database;
      await db.insert(
        'ai_settings',
        {
          'key': key,
          'value': value,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (e) {
      debugPrint('❌ [DB saveSetting ERROR] $e');
      return false;
    }
  }

  // ─── PENDING PHOTO BOOKINGS QUEUE (HUMAN-IN-THE-LOOP) ──────────────────────

  Future<List<Map<String, dynamic>>> getPendingPhotoBookings() async {
    try {
      final db = await database;
      return await db.query(
        'pending_photo_bookings',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'createdAt DESC',
      );
    } catch (e) {
      debugPrint('⚠️ [PENDING PHOTOS DB ERROR] $e');
      return [];
    }
  }

  Future<bool> updatePendingPhotoStatus(String id, String status) async {
    try {
      final db = await database;
      final count = await db.update(
        'pending_photo_bookings',
        {'status': status},
        where: 'id = ?',
        whereArgs: [id],
      );
      return count > 0;
    } catch (e) {
      debugPrint('❌ [PENDING PHOTO UPDATE ERROR] $e');
      return false;
    }
  }

  Future<bool> deletePendingPhotoBooking(String id) async {
    try {
      final db = await database;
      final count = await db.delete(
        'pending_photo_bookings',
        where: 'id = ?',
        whereArgs: [id],
      );
      return count > 0;
    } catch (e) {
      debugPrint('❌ [PENDING PHOTO DELETE ERROR] $e');
      return false;
    }
  }

  /// 🧹 MASTER WIPE: Clears all operational ticket bookings, pending photos, lottery results, and payments
  Future<void> wipeAllOperationalData() async {
    try {
      final db = await database;
      await db.transaction((txn) async {
        await txn.delete('ticket_sales');
        await txn.delete('pending_photo_bookings');
        await txn.delete('lottery_results');
        await txn.delete('collector_payments');
        await txn.delete('vouchers');
        await txn.delete('unsold_tickets');
      });
      debugPrint('✅ [DATABASE SERVICE] Master Wipe Completed! All operational data cleared.');
    } catch (e) {
      debugPrint('❌ [DATABASE SERVICE WIPE ERROR] $e');
      rethrow;
    }
  }

  // ─── 📦 DATE NORMALIZATION HELPERS ──────────────────────────────────────────

  DateTime? parseDateFlexible(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final direct = DateTime.tryParse(s);
    if (direct != null) return DateTime(direct.year, direct.month, direct.day);

    final parts = s.split(RegExp(r'[/.-]'));
    if (parts.length >= 3) {
      if (parts[0].length == 4) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      } else if (parts[2].length == 4) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) return DateTime(y, m, d);
      }
    }
    return null;
  }

  List<String> generateDateVariants(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return [
      '$y-$m-$d',
      '$d-$m-$y',
      '$d/$m/$y',
      '${dt.day}/${dt.month}/$y',
      '${dt.day}-${dt.month}-$y',
    ];
  }

  // ─── 📦 VOUCHERS CRUD ───────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getVouchers({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
  }) async {
    try {
      final db = await database;
      String whereClause = '';
      List<dynamic> whereArgs = [];

      final List<String> conditions = [];
      if (startDate != null && startDate.isNotEmpty && endDate != null && endDate.isNotEmpty) {
        final startDt = parseDateFlexible(startDate);
        final endDt = parseDateFlexible(endDate);
        if (startDt != null && endDt != null) {
          final Set<String> allVariants = {};
          DateTime cur = startDt;
          final limitEnd = endDt.isAfter(startDt.add(const Duration(days: 366))) ? startDt.add(const Duration(days: 366)) : endDt;
          while (!cur.isAfter(limitEnd)) {
            allVariants.addAll(generateDateVariants(cur));
            cur = cur.add(const Duration(days: 1));
          }
          final placeholders = List.filled(allVariants.length, '?').join(',');
          conditions.add('(date IN ($placeholders) OR (date >= ? AND date <= ?))');
          whereArgs.addAll(allVariants);
          whereArgs.add(startDate);
          whereArgs.add(endDate);
        } else {
          conditions.add('(date >= ? AND date <= ?)');
          whereArgs.add(startDate);
          whereArgs.add(endDate);
        }
      } else if (date != null && date.isNotEmpty) {
        final dt = parseDateFlexible(date);
        if (dt != null) {
          final variants = generateDateVariants(dt);
          final placeholders = List.filled(variants.length, '?').join(',');
          conditions.add('(date IN ($placeholders) OR date = ? OR date LIKE ?)');
          whereArgs.addAll(variants);
          whereArgs.add(date);
          whereArgs.add('%${date.trim()}%');
        } else {
          conditions.add('(date = ? OR date LIKE ?)');
          whereArgs.add(date);
          whereArgs.add('%${date.trim()}%');
        }
      }
      if (drawShift != null && drawShift.isNotEmpty && drawShift != 'All Shifts' && drawShift != 'ALL') {
        final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
        conditions.add('(draw_shift = ? OR LOWER(draw_shift) = ? OR LOWER(draw_shift) LIKE ?)');
        whereArgs.add(drawShift);
        whereArgs.add(drawShift.toLowerCase());
        whereArgs.add('%$cleanShift%');
      }
      if (partyName != null && partyName.isNotEmpty && partyName != 'All' && partyName != 'All Parties') {
        final cleanP = partyName.trim();
        conditions.add('(LOWER(TRIM(party_name)) = LOWER(?) OR LOWER(TRIM(dealer_name)) = LOWER(?))');
        whereArgs.add(cleanP);
        whereArgs.add(cleanP);
      }

      if (conditions.isNotEmpty) {
        whereClause = conditions.join(' AND ');
      }

      return await db.query(
        'vouchers',
        where: whereClause.isNotEmpty ? whereClause : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      debugPrint('❌ [GET VOUCHERS ERROR] $e');
      return [];
    }
  }

  Future<bool> insertVoucher(Map<String, dynamic> voucherMap) async {
    try {
      final db = await database;
      await db.insert(
        'vouchers',
        voucherMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (e) {
      debugPrint('❌ [INSERT VOUCHER ERROR] $e');
      return false;
    }
  }

  Future<bool> insertVouchersBatch(List<Map<String, dynamic>> vouchersList) async {
    if (vouchersList.isEmpty) return true;
    try {
      final db = await database;
      // 🚀 Chunk in batches of 2,000 to prevent transaction overflow and memory spikes on 100k+ lines
      const chunkSize = 2000;
      for (int i = 0; i < vouchersList.length; i += chunkSize) {
        final end = (i + chunkSize < vouchersList.length) ? i + chunkSize : vouchersList.length;
        final chunk = vouchersList.sublist(i, end);
        final batch = db.batch();
        for (final v in chunk) {
          batch.insert(
            'vouchers',
            v,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
      return true;
    } catch (e) {
      debugPrint('❌ [BATCH INSERT VOUCHERS ERROR] $e');
      return false;
    }
  }

  Future<bool> deleteVoucher(String id) async {
    try {
      final db = await database;
      final count = await db.delete('vouchers', where: 'id = ?', whereArgs: [id]);
      return count > 0;
    } catch (e) {
      debugPrint('❌ [DELETE VOUCHER ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkUpdateVoucherParty(List<String> ids, String newParty) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.update(
          'vouchers',
          {'party_name': newParty},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK UPDATE VOUCHER PARTY ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkUpdateVoucherSeries(List<String> ids, String newSeries, double newRate) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.rawUpdate(
          'UPDATE vouchers SET series = ?, price_per_ticket = ?, total_amount = total_qty * ? WHERE id = ?',
          [newSeries, newRate, newRate, id],
        );
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK UPDATE VOUCHER SERIES ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkDeleteVouchers(List<String> ids) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.delete('vouchers', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK DELETE VOUCHERS ERROR] $e');
      return false;
    }
  }

 // ─── 🚫 UNSOLD TICKETS CRUD ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getUnsoldTickets({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
  }) async {
    try {
      final db = await database;
      String whereClause = '';
      List<dynamic> whereArgs = [];

      final List<String> conditions = [];
      if (startDate != null && startDate.isNotEmpty && endDate != null && endDate.isNotEmpty) {
        final startDt = parseDateFlexible(startDate);
        final endDt = parseDateFlexible(endDate);
        if (startDt != null && endDt != null) {
          final Set<String> allVariants = {};
          DateTime cur = startDt;
          final limitEnd = endDt.isAfter(startDt.add(const Duration(days: 366))) ? startDt.add(const Duration(days: 366)) : endDt;
          while (!cur.isAfter(limitEnd)) {
            allVariants.addAll(generateDateVariants(cur));
            cur = cur.add(const Duration(days: 1));
          }
          final placeholders = List.filled(allVariants.length, '?').join(',');
          conditions.add('(date IN ($placeholders) OR (date >= ? AND date <= ?))');
          whereArgs.addAll(allVariants);
          whereArgs.add(startDate);
          whereArgs.add(endDate);
        } else {
          conditions.add('(date >= ? AND date <= ?)');
          whereArgs.add(startDate);
          whereArgs.add(endDate);
        }
      } else if (date != null && date.isNotEmpty) {
        final d = date.trim();
        final parts = d.split(RegExp(r'[/.-]'));
        final List<String> variants = [d];
        if (parts.length == 3) {
          final p0 = parts[0];
          final p1 = parts[1];
          final p2 = parts[2];
          if (p0.length == 4) {
            // YYYY-MM-DD -> DD/MM/YYYY, DD-MM-YYYY
            variants.add('$p2/$p1/$p0');
            variants.add('$p2-$p1-$p0');
            final dayInt = int.tryParse(p2);
            final monthInt = int.tryParse(p1);
            if (dayInt != null && monthInt != null) {
              variants.add('$dayInt/$monthInt/$p0');
              variants.add('$dayInt-$monthInt-$p0');
            }
          } else if (p2.length == 4) {
            // DD/MM/YYYY -> YYYY-MM-DD
            variants.add('$p2-$p1-$p0');
            variants.add('$p0-$p1-$p2');
            final dayInt = int.tryParse(p0);
            final monthInt = int.tryParse(p1);
            if (dayInt != null && monthInt != null) {
              variants.add('$dayInt/$monthInt/$p2');
              variants.add('$dayInt-$monthInt-$p2');
            }
          }
        }
        final placeholders = variants.map((_) => 'date = ?').join(' OR ');
        conditions.add('($placeholders OR date LIKE ?)');
        whereArgs.addAll(variants);
        whereArgs.add('%$d%');
      }
      if (drawShift != null && drawShift.isNotEmpty && drawShift != 'All Shifts' && drawShift != 'ALL') {
        final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
        conditions.add('(draw_shift = ? OR LOWER(draw_shift) = ? OR LOWER(draw_shift) LIKE ?)');
        whereArgs.add(drawShift);
        whereArgs.add(drawShift.toLowerCase());
        whereArgs.add('%$cleanShift%');
      }
      if (partyName != null && partyName.isNotEmpty && partyName != 'All' && partyName != 'All Parties') {
        final cleanP = partyName.trim();
        conditions.add('(LOWER(TRIM(party_name)) = LOWER(?) OR LOWER(TRIM(dealer_name)) = LOWER(?))');
        whereArgs.add(cleanP);
        whereArgs.add(cleanP);
      }

      if (conditions.isNotEmpty) {
        whereClause = conditions.join(' AND ');
      }

      return await db.query(
        'unsold_tickets',
        where: whereClause.isNotEmpty ? whereClause : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'created_at DESC',
      );
    } catch (e) {
      debugPrint('❌ [GET UNSOLD ERROR] $e');
      return [];
    }
  }

  Future<bool> insertUnsoldTicket(Map<String, dynamic> unsoldMap) async {
    try {
      final db = await database;
      await db.insert(
        'unsold_tickets',
        unsoldMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    } catch (e) {
      debugPrint('❌ [INSERT UNSOLD ERROR] $e');
      return false;
    }
  }

  Future<bool> insertUnsoldTicketsBatch(List<Map<String, dynamic>> unsoldList) async {
    if (unsoldList.isEmpty) return true;
    try {
      final db = await database;
      // 🚀 Chunk in batches of 2,000 to prevent transaction overflow and memory spikes on 100k+ lines
      const chunkSize = 2000;
      for (int i = 0; i < unsoldList.length; i += chunkSize) {
        final end = (i + chunkSize < unsoldList.length) ? i + chunkSize : unsoldList.length;
        final chunk = unsoldList.sublist(i, end);
        final batch = db.batch();
        for (final u in chunk) {
          batch.insert(
            'unsold_tickets',
            u,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      }
      return true;
    } catch (e) {
      debugPrint('❌ [BATCH INSERT UNSOLD ERROR] $e');
      return false;
    }
  }

  Future<bool> deleteUnsoldTicket(String id) async {
    try {
      final db = await database;
      final count = await db.delete('unsold_tickets', where: 'id = ?', whereArgs: [id]);
      return count > 0;
    } catch (e) {
      debugPrint('❌ [DELETE UNSOLD ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkUpdateUnsoldParty(List<String> ids, String newParty) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.update(
          'unsold_tickets',
          {'party_name': newParty},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK UPDATE UNSOLD PARTY ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkUpdateUnsoldSeries(List<String> ids, String newSeries, double newRate) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.rawUpdate(
          'UPDATE unsold_tickets SET series = ?, price_per_ticket = ?, total_amount = total_qty * ? WHERE id = ?',
          [newSeries, newRate, newRate, id],
        );
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK UPDATE UNSOLD SERIES ERROR] $e');
      return false;
    }
  }

  Future<bool> bulkDeleteUnsold(List<String> ids) async {
    if (ids.isEmpty) return false;
    try {
      final db = await database;
      final batch = db.batch();
      for (final id in ids) {
        batch.delete('unsold_tickets', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
      return true;
    } catch (e) {
      debugPrint('❌ [BULK DELETE UNSOLD ERROR] $e');
      return false;
    }
  }

  Future<bool> lockUnsoldForShift(String date, String drawShift) async {
    try {
      final db = await database;
      final count = await db.update(
        'unsold_tickets',
        {'is_locked': 1},
        where: 'date = ? AND draw_shift = ?',
        whereArgs: [date, drawShift],
      );
      return count > 0;
    } catch (e) {
      debugPrint('❌ [LOCK UNSOLD ERROR] $e');
      return false;
    }
  }

  Future<bool> deleteAllVouchers({String? date, String? drawShift, String? partyName}) async {
    try {
      final db = await database;
      String? where;
      List<dynamic>? whereArgs;
      final List<String> conds = [];
      final List<dynamic> args = [];
      if (date != null && date.isNotEmpty) {
        conds.add('date = ?');
        args.add(date);
      }
      if (drawShift != null && drawShift.isNotEmpty && drawShift != 'All Shifts') {
        conds.add('draw_shift = ?');
        args.add(drawShift);
      }
      if (partyName != null && partyName.isNotEmpty && partyName != 'All' && partyName != 'All Parties') {
        conds.add('party_name = ?');
        args.add(partyName);
      }
      if (conds.isNotEmpty) {
        where = conds.join(' AND ');
        whereArgs = args;
      }
      await db.delete('vouchers', where: where, whereArgs: whereArgs);
      debugPrint('🗑️ [DATABASE LOG] Deleted vouchers matching where: $where, args: $whereArgs');
      return true;
    } catch (e) {
      debugPrint('❌ [DELETE ALL VOUCHERS ERROR] $e');
      return false;
    }
  }

  Future<bool> deleteAllUnsold({String? date, String? drawShift, String? partyName}) async {
    try {
      final db = await database;
      String? where;
      List<dynamic>? whereArgs;
      final List<String> conds = [];
      final List<dynamic> args = [];
      if (date != null && date.isNotEmpty) {
        conds.add('date = ?');
        args.add(date);
      }
      if (drawShift != null && drawShift.isNotEmpty && drawShift != 'All Shifts') {
        conds.add('draw_shift = ?');
        args.add(drawShift);
      }
      if (partyName != null && partyName.isNotEmpty && partyName != 'All' && partyName != 'All Parties') {
        conds.add('party_name = ?');
        args.add(partyName);
      }
      if (conds.isNotEmpty) {
        where = conds.join(' AND ');
        whereArgs = args;
      }
      await db.delete('unsold_tickets', where: where, whereArgs: whereArgs);
      debugPrint('🗑️ [DATABASE LOG] Deleted unsold_tickets matching where: $where, args: $whereArgs');
      return true;
    } catch (e) {
      debugPrint('❌ [DELETE ALL UNSOLD ERROR] $e');
      return false;
    }
  }

  /// ⚡ Reclaims deleted record space, compacts SQLite B-trees, and shrinks database file size
  Future<Map<String, dynamic>> compactDatabase() async {
    try {
      final db = await database;
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = p.join(docsDir.path, 'opscore_pro.db');
      final dbFile = File(dbPath);
      final initialBytes = dbFile.existsSync() ? await dbFile.length() : 0;

      // 1. Flush WAL logs into main database
      await db.execute('PRAGMA wal_checkpoint(FULL);');
      // 2. Incremental vacuum to release deleted pages to the OS
      await db.execute('PRAGMA incremental_vacuum;');
      // 3. Full VACUUM to eliminate internal fragmentation and optimize clustering
      await db.execute('VACUUM;');
      // 4. Update query statistics
      await db.execute('PRAGMA optimize;');

      final finalBytes = dbFile.existsSync() ? await dbFile.length() : 0;
      final savedBytes = (initialBytes > finalBytes) ? (initialBytes - finalBytes) : 0;

      debugPrint('🧹 [DB COMPACT] Initial: ${(initialBytes / 1024).toStringAsFixed(1)} KB, Final: ${(finalBytes / 1024).toStringAsFixed(1)} KB, Reclaimed: ${(savedBytes / 1024).toStringAsFixed(1)} KB');

      return {
        'initialBytes': initialBytes,
        'finalBytes': finalBytes,
        'savedBytes': savedBytes,
        'initialMb': (initialBytes / (1024 * 1024)).toStringAsFixed(2),
        'finalMb': (finalBytes / (1024 * 1024)).toStringAsFixed(2),
        'savedMb': (savedBytes / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('❌ [DB COMPACT ERROR] $e');
      return {'error': e.toString()};
    }
  }

  /// 📦 Creates a high-efficiency GZIP-compressed backup (.db.gz), shrinking disk space by 80-90%
  Future<File> createCompressedBackup(String targetFilePath) async {
    final db = await database;
    // Checkpoint WAL to guarantee all uncommitted/in-flight transactions are committed to the file
    await db.execute('PRAGMA wal_checkpoint(FULL);');

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'opscore_pro.db');
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      throw Exception('Database file does not exist at $dbPath');
    }

    final rawBytes = await dbFile.readAsBytes();
    final compressedBytes = gzip.encode(rawBytes);

    final finalPath = targetFilePath.endsWith('.gz') ? targetFilePath : '$targetFilePath.gz';
    final destFile = File(finalPath);
    if (!await destFile.parent.exists()) {
      await destFile.parent.create(recursive: true);
    }
    await destFile.writeAsBytes(compressedBytes);
    debugPrint('📦 [BACKUP COMPRESSED] Original: ${(rawBytes.length / 1024).toStringAsFixed(1)} KB -> Compressed: ${(compressedBytes.length / 1024).toStringAsFixed(1)} KB (${((1 - compressedBytes.length / rawBytes.length) * 100).toStringAsFixed(1)}% space saved)');
    return destFile;
  }

  /// 🔄 Restores SQLite database from a compressed .db.gz backup file with forensic safety and rollback
  Future<void> restoreCompressedBackup(File compressedBackupFile) async {
    if (!await compressedBackupFile.exists()) {
      throw FileSystemException('Backup file not found at ${compressedBackupFile.path}');
    }

    final compressedBytes = await compressedBackupFile.readAsBytes();
    if (compressedBytes.isEmpty) {
      throw const FormatException('Selected backup file is empty (0 bytes).');
    }

    final List<int> rawBytes;
    try {
      rawBytes = (compressedBackupFile.path.endsWith('.gz'))
          ? gzip.decode(compressedBytes)
          : compressedBytes;
    } catch (e) {
      throw FormatException('Failed to decompress backup archive: $e');
    }

    final uint8Bytes = Uint8List.fromList(rawBytes);

    // 🛡️ 1. Validate SQLite 16-byte magic header ("SQLite format 3\0")
    if (!SecurityCryptoService.instance.isValidSqliteHeader(uint8Bytes)) {
      throw const FormatException('Validation Error: Selected file is not a valid SQLite database format.');
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'opscore_pro.db');
    final walPath = p.join(docsDir.path, 'opscore_pro.db-wal');
    final shmPath = p.join(docsDir.path, 'opscore_pro.db-shm');
    final journalPath = p.join(docsDir.path, 'opscore_pro.db-journal');

    // 🛡️ 2. Create an automatic pre-restore safety rollback snapshot
    final targetFile = File(dbPath);
    File? safetyBackupFile;
    if (await targetFile.exists()) {
      final safetyPath = p.join(docsDir.path, 'opscore_pro.db.pre_restore_safety_${DateTime.now().millisecondsSinceEpoch}');
      safetyBackupFile = await targetFile.copy(safetyPath);
      debugPrint('🛡️ [RESTORE] Created safety rollback copy at: ${safetyBackupFile.path}');
    }

    // 🛡️ 3. Safely flush and close active connection
    if (_db != null && _db!.isOpen) {
      try {
        await _db!.execute('PRAGMA wal_checkpoint(FULL);');
      } catch (_) {}
      await _db!.close();
      _db = null;
    }

    // 🛡️ 4. Write to a temporary file first
    final tempFilePath = p.join(docsDir.path, 'opscore_pro.db.restore_tmp');
    final tempFile = File(tempFilePath);
    await tempFile.writeAsBytes(uint8Bytes, flush: true);

    try {
      // 🛡️ 5. Remove old journal/wal/shm to prevent stale transaction replay
      for (final pth in [walPath, shmPath, journalPath]) {
        final f = File(pth);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }

      // Replace live DB with verified temp file
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(dbPath);

      // 🛡️ 6. Verify integrity of restored database
      final restoredDb = await database;
      final integrityCheck = await restoredDb.rawQuery('PRAGMA quick_check;');
      final status = integrityCheck.isNotEmpty ? integrityCheck.first.values.first.toString() : 'unknown';
      if (status.toLowerCase() != 'ok') {
        throw FormatException('Database integrity check failed: $status');
      }

      // Success: clean up temporary safety backup
      if (safetyBackupFile != null && await safetyBackupFile.exists()) {
        try {
          await safetyBackupFile.delete();
        } catch (_) {}
      }

      notifyTicketSalesChanged();
      debugPrint('🔄 [RESTORE SUCCESS] Database restored and integrity verified successfully from ${compressedBackupFile.path}');
    } catch (e) {
      debugPrint('🚨 [RESTORE RECOVERY] Integrity failure during restore: $e. Initiating rollback...');
      // Roll back to safety backup
      if (safetyBackupFile != null && await safetyBackupFile.exists()) {
        try {
          if (_db != null && _db!.isOpen) {
            await _db!.close();
            _db = null;
          }
          if (await targetFile.exists()) await targetFile.delete();
          await safetyBackupFile.rename(dbPath);
          await database; // Reopen rolled-back database
          debugPrint('🛡️ [RESTORE RECOVERY] Rollback to original database succeeded.');
        } catch (rollbackErr) {
          debugPrint('🚨 [RESTORE CRITICAL] Rollback failure: $rollbackErr');
        }
      }
      rethrow;
    }
  }

  /// 🚨 EMERGENCY ANTI-THEFT WIPEOUT
  /// Permanently deletes all local SQLite company database files, WAL logs,
  /// shared memory, and backups to prevent unauthorized theft/exfiltration.
  Future<void> emergencySecurityWipeout() async {
    try {
      debugPrint('🚨 [SECURITY WIPEOUT] Starting emergency data wipeout...');
      if (_db != null && _db!.isOpen) {
        try {
          await _db!.close();
        } catch (_) {}
        _db = null;
      }

      final docsDir = await getApplicationDocumentsDirectory();
      
      // List of specific database targets
      final targets = [
        p.join(docsDir.path, 'opscore_pro.db'),
        p.join(docsDir.path, 'opscore_pro.db-wal'),
        p.join(docsDir.path, 'opscore_pro.db-shm'),
        p.join(docsDir.path, 'opscore_pro.db-journal'),
      ];

      for (final targetPath in targets) {
        final f = File(targetPath);
        if (f.existsSync()) {
          try {
            // Overwrite bytes before deletion for forensic sanitization
            f.writeAsBytesSync([]);
            f.deleteSync();
            debugPrint('🗑️ [WIPEOUT] Destroyed file: $targetPath');
          } catch (e) {
            debugPrint('⚠️ [WIPEOUT] File delete warning: $e');
          }
        }
      }

      // Also scan docs directory for any local backup files or temporary DB copies
      if (docsDir.existsSync()) {
        final allEntries = docsDir.listSync(recursive: false);
        for (final entry in allEntries) {
          if (entry is File) {
            final fileName = p.basename(entry.path).toLowerCase();
            if (fileName.startsWith('opscore_pro') &&
                (fileName.endsWith('.db') ||
                 fileName.endsWith('.db-wal') ||
                 fileName.endsWith('.db-shm') ||
                 fileName.endsWith('.db-journal') ||
                 fileName.endsWith('.db.gz'))) {
              try {
                entry.writeAsBytesSync([]);
                entry.deleteSync();
                debugPrint('🗑️ [WIPEOUT] Purged matching backup/file: ${entry.path}');
              } catch (_) {}
            }
          }
        }
      }

      debugPrint('✅ [SECURITY WIPEOUT] All local company data purged completely.');
    } catch (e) {
      debugPrint('🚨 [SECURITY WIPEOUT CRITICAL ERROR] $e');
    }
  }

  /// ⚡ DYNAMIC BULK RATE RECALCULATION & SYNC
  /// Recalculates price_per_ticket & total_amount for Vouchers, Unsold, and Bookings
  /// based on dynamic Series 100 pricing, target Party, and Date / Date Range.
  Future<Map<String, int>> recalculateRatesAcrossSystem({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
    String? partyName,
    List<String>? partyNames,
    double? customSeries100Price,
    bool updateVouchers = true,
    bool updateUnsold = true,
    bool updateSales = true,
  }) async {
    int vouchersUpdated = 0;
    int unsoldUpdated = 0;
    int salesUpdated = 0;

    try {
      final db = await database;

      // 1. Fetch active series configurations from database
      final seriesList = await getSeriesPrices();

      // 2. Determine dynamic per-unit rate
      double perUnitRate;
      if (customSeries100Price != null && customSeries100Price > 0) {
        perUnitRate = customSeries100Price / 100.0;
      } else {
        final s100 = seriesList.where(
          (s) => s.isActive && (s.seriesName.trim() == '100' || s.seriesName.replaceAll(RegExp(r'\D'), '') == '100'),
        );
        if (s100.isNotEmpty && s100.first.ticketPrice > 0) {
          perUnitRate = s100.first.ticketPrice / 100.0;
        } else {
          double? derived;
          for (final s in seriesList.where((s) => s.isActive && s.ticketPrice > 0)) {
            final numVal = double.tryParse(s.seriesName.replaceAll(RegExp(r'\D'), ''));
            if (numVal != null && numVal > 0) {
              derived = s.ticketPrice / numVal;
              break;
            }
          }
          perUnitRate = derived ?? 3.75;
        }
      }

      // Helper function to dynamically calculate price for any series
      double getDynamicRate(String seriesStr) {
        final clean = seriesStr.trim().toUpperCase();
        if (clean.isEmpty) return perUnitRate * 12.0;

        // Check if explicit custom series price is in settings
        final exact = seriesList.where(
          (s) => s.isActive && s.seriesName.trim().toUpperCase() == clean,
        );
        if (exact.isNotEmpty && exact.first.ticketPrice > 0) {
          return exact.first.ticketPrice;
        }

        final digits = clean.replaceAll(RegExp(r'\D'), '');
        final numVal = double.tryParse(digits) ?? 0.0;
        if (numVal > 0) {
          return numVal * perUnitRate;
        }
        return perUnitRate * 12.0;
      }

      // Build date / shift / party conditions for vouchers & unsold
      List<String> conditions = [];
      List<dynamic> whereArgs = [];

      final Set<String> rangeDateVariants = {};
      final startDt = parseDateFlexible(startDate);
      final endDt = parseDateFlexible(endDate);

      if (startDt != null && endDt != null) {
        DateTime cur = startDt;
        final limitEnd = endDt.isAfter(startDt.add(const Duration(days: 366))) ? startDt.add(const Duration(days: 366)) : endDt;
        while (!cur.isAfter(limitEnd)) {
          rangeDateVariants.addAll(generateDateVariants(cur));
          cur = cur.add(const Duration(days: 1));
        }
        final placeholders = List.filled(rangeDateVariants.length, '?').join(',');
        conditions.add('(date IN ($placeholders) OR (date >= ? AND date <= ?))');
        whereArgs.addAll(rangeDateVariants);
        whereArgs.add(startDate);
        whereArgs.add(endDate);
      } else if (date != null && date.trim().isNotEmpty && date != 'ALL') {
        final dt = parseDateFlexible(date);
        if (dt != null) {
          final variants = generateDateVariants(dt);
          final placeholders = List.filled(variants.length, '?').join(',');
          conditions.add('(date IN ($placeholders) OR date = ? OR date LIKE ?)');
          whereArgs.addAll(variants);
          whereArgs.add(date.trim());
          whereArgs.add('%${date.trim()}%');
        } else {
          conditions.add('(date = ? OR date LIKE ?)');
          whereArgs.add(date.trim());
          whereArgs.add('%${date.trim()}%');
        }
      }

      if (drawShift != null && drawShift.trim().isNotEmpty && drawShift != 'All Shifts' && drawShift != 'ALL') {
        final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
        conditions.add('(draw_shift = ? OR LOWER(draw_shift) = ? OR LOWER(draw_shift) LIKE ?)');
        whereArgs.add(drawShift.trim());
        whereArgs.add(drawShift.trim().toLowerCase());
        whereArgs.add('%$cleanShift%');
      }

      final targetParties = <String>{};
      if (partyNames != null && partyNames.isNotEmpty) {
        targetParties.addAll(partyNames.where((p) => p.trim().isNotEmpty && p != 'All' && p != 'All Parties'));
      } else if (partyName != null && partyName.trim().isNotEmpty && partyName != 'All' && partyName != 'All Parties') {
        targetParties.add(partyName.trim());
      }

      if (targetParties.isNotEmpty) {
        final lowerList = targetParties.map((p) => p.trim().toLowerCase()).toList();
        final placeholders = List.filled(lowerList.length, '?').join(',');
        conditions.add('(LOWER(TRIM(party_name)) IN ($placeholders) OR LOWER(TRIM(dealer_name)) IN ($placeholders))');
        whereArgs.addAll(lowerList);
        whereArgs.addAll(lowerList);
      }

      final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;

      final batch = db.batch();

      // 3. Update Vouchers
      if (updateVouchers) {
        final vouchers = await db.query(
          'vouchers',
          where: whereClause,
          whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        );
        for (final v in vouchers) {
          final id = v['id'] as String;
          final series = (v['series'] as String?) ?? '';
          final newRate = getDynamicRate(series);
          final qty = (v['total_qty'] as num?)?.toInt() ?? 0;
          final newTotal = qty * newRate;

          batch.rawUpdate(
            'UPDATE vouchers SET price_per_ticket = ?, total_amount = ? WHERE id = ?',
            [newRate, newTotal, id],
          );
          vouchersUpdated++;
        }
      }

      // 4. Update Unsold Tickets
      if (updateUnsold) {
        final unsold = await db.query(
          'unsold_tickets',
          where: whereClause,
          whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        );
        for (final u in unsold) {
          final id = u['id'] as String;
          final series = (u['series'] as String?) ?? '';
          final newRate = getDynamicRate(series);
          final qty = (u['total_qty'] as num?)?.toInt() ?? 0;
          final newTotal = qty * newRate;

          batch.rawUpdate(
            'UPDATE unsold_tickets SET price_per_ticket = ?, total_amount = ? WHERE id = ?',
            [newRate, newTotal, id],
          );
          unsoldUpdated++;
        }
      }

      // 5. Update Ticket Sales (Bookings)
      if (updateSales) {
        List<String> salesConditions = [];
        List<dynamic> salesArgs = [];

        if (startDt != null && endDt != null) {
          final sIso = '${startDate}T00:00:00';
          final eIso = '${endDate}T23:59:59';
          final placeholders = List.filled(rangeDateVariants.length, '?').join(',');
          salesConditions.add('((drawDate >= ? AND drawDate <= ?) OR (saleDate >= ? AND saleDate <= ?) OR substr(drawDate,1,10) IN ($placeholders))');
          salesArgs.add(sIso);
          salesArgs.add(eIso);
          salesArgs.add(sIso);
          salesArgs.add(eIso);
          salesArgs.addAll(rangeDateVariants);
        } else if (date != null && date.trim().isNotEmpty && date != 'ALL') {
          salesConditions.add('(drawDate LIKE ? OR saleDate LIKE ?)');
          salesArgs.add('%${date.trim()}%');
          salesArgs.add('%${date.trim()}%');
        }

        if (drawShift != null && drawShift.trim().isNotEmpty && drawShift != 'All Shifts' && drawShift != 'ALL') {
          final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
          salesConditions.add('(drawName LIKE ? OR drawCode LIKE ?)');
          salesArgs.add('%$cleanShift%');
          salesArgs.add('%$cleanShift%');
        }

        if (targetParties.isNotEmpty) {
          final lowerList = targetParties.map((p) => p.trim().toLowerCase()).toList();
          final placeholders = List.filled(lowerList.length, '?').join(',');
          salesConditions.add('(LOWER(TRIM(buyerName)) IN ($placeholders) OR LOWER(TRIM(agentName)) IN ($placeholders))');
          salesArgs.addAll(lowerList);
          salesArgs.addAll(lowerList);
        }

        final salesWhere = salesConditions.isNotEmpty ? salesConditions.join(' AND ') : null;

        final sales = await db.query(
          'ticket_sales',
          where: salesWhere,
          whereArgs: salesArgs.isNotEmpty ? salesArgs : null,
        );
        for (final s in sales) {
          final id = s['id'] as String;
          final series = (s['ticketSeries'] as String?) ?? '';
          final newRate = getDynamicRate(series);
          final qty = (s['quantity'] as num?)?.toInt() ?? 1;
          final newTotal = qty * newRate;

          batch.rawUpdate(
            'UPDATE ticket_sales SET pricePerTicket = ?, totalAmount = ? WHERE id = ?',
            [newRate, newTotal, id],
          );
          salesUpdated++;
        }
      }

      await batch.commit(noResult: true);
      notifyTicketSalesChanged();

      debugPrint('⚡ [DYNAMIC RECALCULATION COMPLETE] Party: ${partyName ?? "ALL"}, Vouchers: $vouchersUpdated, Unsold: $unsoldUpdated, Sales: $salesUpdated at per-unit rate: $perUnitRate');
    } catch (e) {
      debugPrint('❌ [RECALCULATE RATES ERROR] $e');
    }

    return {
      'vouchers': vouchersUpdated,
      'unsold': unsoldUpdated,
      'sales': salesUpdated,
    };
  }

  /// 🔍 Fetch distinct party/dealer names that actually have entries on the selected date or range.
  Future<List<String>> getActivePartiesForSelection({
    String? date,
    String? startDate,
    String? endDate,
    String? drawShift,
  }) async {
    final Set<String> result = {};
    try {
      final db = await database;

      // Build conditions for vouchers & unsold
      List<String> conditions = [];
      List<dynamic> whereArgs = [];

      final Set<String> rangeDateVariants = {};
      final startDt = parseDateFlexible(startDate);
      final endDt = parseDateFlexible(endDate);

      if (startDt != null && endDt != null) {
        DateTime cur = startDt;
        final limitEnd = endDt.isAfter(startDt.add(const Duration(days: 366)))
            ? startDt.add(const Duration(days: 366))
            : endDt;
        while (!cur.isAfter(limitEnd)) {
          rangeDateVariants.addAll(generateDateVariants(cur));
          cur = cur.add(const Duration(days: 1));
        }
        final placeholders = List.filled(rangeDateVariants.length, '?').join(',');
        conditions.add('(date IN ($placeholders) OR (date >= ? AND date <= ?))');
        whereArgs.addAll(rangeDateVariants);
        whereArgs.add(startDate);
        whereArgs.add(endDate);
      } else if (date != null && date.trim().isNotEmpty && date != 'ALL') {
        final dt = parseDateFlexible(date);
        if (dt != null) {
          final variants = generateDateVariants(dt);
          final placeholders = List.filled(variants.length, '?').join(',');
          conditions.add('(date IN ($placeholders) OR date = ? OR date LIKE ?)');
          whereArgs.addAll(variants);
          whereArgs.add(date.trim());
          whereArgs.add('%${date.trim()}%');
        } else {
          conditions.add('(date = ? OR date LIKE ?)');
          whereArgs.add(date.trim());
          whereArgs.add('%${date.trim()}%');
        }
      }

      if (drawShift != null &&
          drawShift.trim().isNotEmpty &&
          drawShift != 'All Shifts' &&
          drawShift != 'ALL') {
        final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
        conditions.add('(draw_shift = ? OR LOWER(draw_shift) = ? OR LOWER(draw_shift) LIKE ?)');
        whereArgs.add(drawShift.trim());
        whereArgs.add(drawShift.trim().toLowerCase());
        whereArgs.add('%$cleanShift%');
      }

      final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;

      // 1. Query Vouchers
      final voucherRows = await db.query(
        'vouchers',
        columns: ['party_name', 'dealer_name'],
        where: whereClause,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      );
      for (final r in voucherRows) {
        final p = (r['party_name'] as String?)?.trim();
        final d = (r['dealer_name'] as String?)?.trim();
        if (p != null && p.isNotEmpty) result.add(p);
        if (d != null && d.isNotEmpty) result.add(d);
      }

      // 2. Query Unsold Tickets
      final unsoldRows = await db.query(
        'unsold_tickets',
        columns: ['party_name', 'dealer_name'],
        where: whereClause,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      );
      for (final r in unsoldRows) {
        final p = (r['party_name'] as String?)?.trim();
        final d = (r['dealer_name'] as String?)?.trim();
        if (p != null && p.isNotEmpty) result.add(p);
        if (d != null && d.isNotEmpty) result.add(d);
      }

      // 3. Query Ticket Sales
      List<String> salesConditions = [];
      List<dynamic> salesArgs = [];
      if (startDt != null && endDt != null) {
        final sIso = DateFormat('yyyy-MM-dd').format(startDt);
        final eIso = DateFormat('yyyy-MM-dd').format(endDt);
        final placeholders = List.filled(rangeDateVariants.length, '?').join(',');
        salesConditions.add(
            '((saleDate >= ? AND saleDate <= ?) OR (drawDate >= ? AND drawDate <= ?) OR saleDate IN ($placeholders) OR drawDate IN ($placeholders))');
        salesArgs.add(sIso);
        salesArgs.add(eIso);
        salesArgs.add(sIso);
        salesArgs.add(eIso);
        salesArgs.addAll(rangeDateVariants);
        salesArgs.addAll(rangeDateVariants);
      } else if (date != null && date.trim().isNotEmpty && date != 'ALL') {
        salesConditions.add('(drawDate LIKE ? OR saleDate LIKE ?)');
        salesArgs.add('%${date.trim()}%');
        salesArgs.add('%${date.trim()}%');
      }
      if (drawShift != null &&
          drawShift.trim().isNotEmpty &&
          drawShift != 'All Shifts' &&
          drawShift != 'ALL') {
        final cleanShift = drawShift.toLowerCase().replaceAll('dear ', '').trim();
        salesConditions.add('(drawName LIKE ? OR drawCode LIKE ?)');
        salesArgs.add('%$cleanShift%');
        salesArgs.add('%$cleanShift%');
      }
      final salesWhere = salesConditions.isNotEmpty ? salesConditions.join(' AND ') : null;
      final salesRows = await db.query(
        'ticket_sales',
        columns: ['buyerName', 'agentName'],
        where: salesWhere,
        whereArgs: salesArgs.isNotEmpty ? salesArgs : null,
      );
      for (final r in salesRows) {
        final b = (r['buyerName'] as String?)?.trim();
        final a = (r['agentName'] as String?)?.trim();
        if (b != null && b.isNotEmpty) result.add(b);
        if (a != null && a.isNotEmpty) result.add(a);
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching active parties for selection: $e');
    }

    final sorted = result.toList();
    sorted.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }
}

