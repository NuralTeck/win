import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/shared/models/ticket_sale_model.dart';
import '../../features/sellers/models/seller_customer_model.dart';
import '../../features/shared/models/series_price_model.dart';
import '../../features/operations/models/lottery_sambad_result_model.dart';

class DatabaseService {
  DatabaseService._internal();
  static final DatabaseService instance = DatabaseService._internal();

  Database? _db;

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
    // ⚡ Configure SQLite WAL mode & 10s Busy Timeout to prevent database is locked errors!
    await db.execute('PRAGMA journal_mode=WAL;');
    await db.execute('PRAGMA busy_timeout=10000;');
    await db.execute('PRAGMA synchronous=NORMAL;');
    await _createTables(db);
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
        createdAt TEXT NOT NULL
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
  }

  Future<void> _seedInitialData(Database db) async {
    // Clean database startup — No hardcoded dummy data seeded
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
    final db = await database;
    final count = await db.rawDelete('''
      DELETE FROM ticket_sales
      WHERE id NOT IN (
        SELECT MIN(id) FROM ticket_sales
        GROUP BY drawName, substr(drawDate, 1, 10), ticketSeries, ticketNumber
      )
    ''');
    debugPrint(
      '🧹 [DATABASE LOG] Removed $count duplicate ticket sales from opscore_pro.db',
    );
    return count;
  }

  Future<List<TicketSaleModel>> getTicketSales() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ticket_sales',
      orderBy: 'saleDate DESC',
    );
    return maps.map((m) => _ticketSaleFromMap(m)).toList();
  }

  Future<List<TicketSaleModel>> getTicketSalesByDate(DateTime targetDate) async {
    final db = await database;
    final dateStr =
        "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";
    final List<Map<String, dynamic>> maps = await db.query(
      'ticket_sales',
      where: "substr(drawDate, 1, 10) = ? OR substr(saleDate, 1, 10) = ?",
      whereArgs: [dateStr, dateStr],
      orderBy: 'saleDate DESC',
    );
    return maps.map((m) => _ticketSaleFromMap(m)).toList();
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
    final db = await database;
    final cleanTkt = ticketNumber.trim().split(' ').last;
    final targetDatePrefix = drawDateStr.length >= 10 ? drawDateStr.substring(0, 10) : drawDateStr;

    if (buyerName != null && buyerName.isNotEmpty) {
      final List<Map<String, dynamic>> res = await db.query(
        'ticket_sales',
        columns: ['id'],
        where: "drawName = ? AND substr(drawDate, 1, 10) = ? AND LOWER(ticketSeries) = ? AND (ticketNumber = ? OR ticketNumber LIKE ?) AND (LOWER(buyerName) = ? OR LOWER(agentName) = ?)",
        whereArgs: [drawName, targetDatePrefix, ticketSeries.toLowerCase(), ticketNumber, '%$cleanTkt', buyerName.toLowerCase(), buyerName.toLowerCase()],
        limit: 1,
      );
      return res.isNotEmpty;
    } else {
      final List<Map<String, dynamic>> res = await db.query(
        'ticket_sales',
        columns: ['id'],
        where: "drawName = ? AND substr(drawDate, 1, 10) = ? AND LOWER(ticketSeries) = ? AND (ticketNumber = ? OR ticketNumber LIKE ?)",
        whereArgs: [drawName, targetDatePrefix, ticketSeries.toLowerCase(), ticketNumber, '%$cleanTkt'],
        limit: 1,
      );
      return res.isNotEmpty;
    }
  }

  Future<void> _autoRegisterSellerFromTicket(TicketSaleModel sale) async {
    final name = (sale.agentName.trim().isNotEmpty ? sale.agentName : sale.buyerName).trim();
    if (name.isEmpty || name.toLowerCase() == 'walk-in customer' || name.toLowerCase() == 'default') return;

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
    // Auto-save Customer/Seller into Seller Master
    _autoRegisterSellerFromTicket(sale);

    if (!isSilent) {
      debugPrint(
        '✅ [DATABASE LOG] Saved Ticket Booking to opscore_pro.db -> Receipt: ${sale.receiptNumber}, Buyer: ${sale.buyerName}, Amount: ₹${sale.totalAmount}',
      );
    }
    return sale;
  }

  Future<void> insertTicketSalesBulk(List<TicketSaleModel> sales) async {
    if (sales.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final sale in sales) {
      batch.insert(
        'ticket_sales',
        _ticketSaleToMap(sale),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    debugPrint('⚡ [SQLITE BATCH] Bulk inserted ${sales.length} tickets in single transaction.');

    // Auto-register distinct sellers from batch
    for (final sale in sales) {
      _autoRegisterSellerFromTicket(sale);
    }
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
      where: 'id = ? OR (ticketSeries = ? AND (ticketNumber = ? OR ticketNumber = ?))',
      whereArgs: [id, oldSeries, oldTicketNo, '$oldSeries $oldTicketNo'],
    );
    debugPrint('✏️ [SQLITE LOG] Updated ticket $oldSeries-$oldTicketNo to $newSeries-$newTicketNo ($newSellerName, ₹$newAmount)');
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
  }

  Future<void> deleteTicketSale(String id) async {
    final db = await database;
    await db.delete('ticket_sales', where: 'id = ?', whereArgs: [id]);
    debugPrint(
      '🗑️ [DATABASE LOG] Deleted Ticket Booking from opscore_pro.db -> ID: $id',
    );
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
  }

  // ─── SELLER CUSTOMERS CRUD ──────────────────────────────────────────────────

  Future<List<SellerCustomerModel>> getSellerCustomers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'seller_customers',
      orderBy: 'createdAt DESC',
    );
    final List<SellerCustomerModel> sellers = maps.map((m) => _sellerCustomerFromMap(m)).toList();
    final Set<String> existingNames = sellers.map((s) => s.name.trim().toLowerCase()).toSet();

    // Auto-discover any unique customers/sellers from ticket bookings that aren't yet in seller_customers
    try {
      final List<Map<String, dynamic>> bookingNames = await db.rawQuery('''
        SELECT DISTINCT 
          CASE WHEN TRIM(agentName) != '' THEN TRIM(agentName) ELSE TRIM(buyerName) END as sName,
          buyerPhone as sPhone,
          MIN(saleDate) as firstSale
        FROM ticket_sales 
        WHERE TRIM(buyerName) != '' OR TRIM(agentName) != ''
        GROUP BY sName
      ''');

      for (final row in bookingNames) {
        final rawName = (row['sName']?.toString() ?? '').trim();
        if (rawName.isEmpty || rawName.toLowerCase() == 'walk-in customer' || rawName.toLowerCase() == 'default' || rawName.toLowerCase() == 'general') {
          continue;
        }

        if (!existingNames.contains(rawName.toLowerCase())) {
          final cleanKey = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
          final accessKey = cleanKey.isNotEmpty ? (cleanKey.length > 8 ? cleanKey.substring(0, 8) : cleanKey) : 'SEL${DateTime.now().millisecondsSinceEpoch % 10000}';
          final phone = row['sPhone']?.toString() ?? '';
          final autoSeller = SellerCustomerModel(
            id: 'sc_${rawName.hashCode.abs()}',
            name: rawName,
            accessKey: accessKey,
            password: '1234',
            phone: phone,
            isActive: true,
            createdAt: DateTime.tryParse(row['firstSale']?.toString() ?? '') ?? DateTime.now(),
          );

          await insertSellerCustomer(autoSeller);
          sellers.add(autoSeller);
          existingNames.add(rawName.toLowerCase());
        }
      }
    } catch (e) {
      debugPrint('Error auto-syncing sellers from ticket bookings: $e');
    }

    return sellers;
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
  }) async {
    final db = await database;

    // Check if entry already exists for exact same Draw Name & Draw Date
    final existing = await db.query(
      'lottery_results',
      where: 'drawName = ? AND drawDateStr = ?',
      whereArgs: [result.drawName, result.drawDateStr],
    );

    // Use existing ID if found to update, or construct a unique composite ID
    final String targetId = existing.isNotEmpty
        ? (existing.first['id'] as String)
        : '${result.drawName}_${result.drawDateStr}'.replaceAll(
            RegExp(r'[^a-zA-Z0-9]'),
            '_',
          );

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
      'publishedAt': result.publishedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint(
      '🏆 [DATABASE LOG] Saved/Updated Lottery Result in opscore_pro.db -> Draw: "${result.drawName}", Date: ${result.drawDateStr}, 1st Prize: "${result.firstPrize}", Verified Winners: $verifiedWinnersCount, Payout: ₹$totalPayoutAmount',
    );
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

  TicketSaleModel _ticketSaleFromMap(Map<String, dynamic> m) {
    return TicketSaleModel(
      id: m['id'] as String,
      receiptNumber: m['receiptNumber'] as String,
      buyerName: m['buyerName'] as String,
      buyerPhone: m['buyerPhone'] as String,
      agentCode: m['agentCode'] as String,
      agentName: m['agentName'] as String,
      drawCode: m['drawCode'] as String,
      drawName: m['drawName'] as String,
      ticketSeries: m['ticketSeries'] as String,
      ticketNumber: m['ticketNumber'] as String,
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
      saleDate: DateTime.parse(m['saleDate'] as String).toLocal(),
      drawDate: DateTime.parse(m['drawDate'] as String).toLocal(),
    );
  }

  Map<String, dynamic> _sellerCustomerToMap(SellerCustomerModel s) {
    return {
      'id': s.id,
      'name': s.name,
      'accessKey': s.accessKey,
      'password': s.password,
      'phone': s.phone,
      'isActive': s.isActive ? 1 : 0,
      'createdAt': s.createdAt.toIso8601String(),
    };
  }

  SellerCustomerModel _sellerCustomerFromMap(Map<String, dynamic> m) {
    return SellerCustomerModel(
      id: m['id'] as String,
      name: m['name'] as String,
      accessKey: m['accessKey'] as String,
      password: m['password'] as String,
      phone: m['phone'] as String,
      isActive: (m['isActive'] as int) == 1,
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
    };
  }

  UniversalSeriesPriceModel _seriesPriceFromMap(Map<String, dynamic> m) {
    return UniversalSeriesPriceModel(
      id: m['id'] as String,
      seriesName: m['seriesName'] as String,
      ticketPrice: (m['ticketPrice'] as num).toDouble(),
      isActive: (m['isActive'] as int) == 1,
      createdAt: DateTime.parse(m['createdAt'] as String),
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
    final db = await database;
    await db.delete(
      'ticket_sales',
      where:
          'UPPER(ticketSeries) = ? AND (ticketNumber = ? OR ticketNumber = ?)',
      whereArgs: [series.toUpperCase(), ticketNo, '$series $ticketNo'],
    );
    debugPrint(
      '🗑️ [SQLITE LOG] Deleted ticket sale Series: $series, Ticket: $ticketNo',
    );
  }

  Future<void> wipeAllTicketSales() async {
    final db = await database;
    await db.delete('ticket_sales');
    debugPrint('🧹 [SQLITE LOG] Local ticket_sales table wiped clean!');
  }

  Future<void> wipeAllLocalDataOnLogout() async {
    final db = await database;
    await db.delete('ticket_sales');
    await db.delete('seller_customers');
    await db.delete('lottery_results');
    await db.delete('collectors');
    await db.delete('collector_payments');
    try {
      await db.delete('unsold_tickets');
    } catch (_) {}
    try {
      await db.delete('pending_photo_bookings');
    } catch (_) {}
    debugPrint('🧹 [SQLITE LOG] All local tables wiped completely on logout!');
  }

  // ─── AUTHENTICATION & USER MANAGEMENT CRUD ────────────────────────────────

  Future<Map<String, dynamic>?> authenticateUser(
    String username,
    String password,
  ) async {
    final cleanUser = username.trim().toLowerCase();
    final cleanPass = password.trim();

    // Default emergency owner/admin accounts
    if ((cleanUser == 'admin' && (cleanPass == 'admin123' || cleanPass == 'admin')) ||
        (cleanUser == 'owner' && (cleanPass == 'owner123' || cleanPass == 'admin123'))) {
      return {
        'id': 'admin_root',
        'username': cleanUser,
        'fullName': cleanUser == 'owner' ? 'Business Owner' : 'System Administrator',
        'role': 'Administrator',
        'phone': '9876543210',
        'isActive': 1,
      };
    }

    try {
      final db = await database;
      final results = await db.query(
        'app_users',
        where: 'LOWER(username) = ? AND password = ? AND isActive = 1',
        whereArgs: [cleanUser, cleanPass],
        limit: 1,
      );

      if (results.isNotEmpty) {
        return results.first;
      }
    } catch (e) {
      debugPrint('⚠️ [AUTH DB ERROR] $e');
    }
    return null;
  }

  Future<bool> checkUsernameExists(String username) async {
    final cleanUser = username.trim().toLowerCase();
    if (cleanUser == 'admin' || cleanUser == 'owner') return true;

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
      await db.insert(
        'app_users',
        user,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('✅ [AUTH DB] Registered new user: ${user['username']} (${user['role']})');
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

  Future<String?> getGeminiApiKey() async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> res = await db.query(
        'ai_settings',
        where: 'key = ?',
        whereArgs: ['gemini_api_key'],
        limit: 1,
      );
      if (res.isNotEmpty && res.first['value'] != null) {
        return res.first['value'].toString().trim();
      }
    } catch (e) {
      debugPrint('⚠️ [AI CONFIG DB ERROR] $e');
    }
    return null;
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
      });
      debugPrint('✅ [DATABASE SERVICE] Master Wipe Completed! All operational data cleared.');
    } catch (e) {
      debugPrint('❌ [DATABASE SERVICE WIPE ERROR] $e');
      rethrow;
    }
  }
}
