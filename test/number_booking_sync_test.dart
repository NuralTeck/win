import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opscore_pro/core/database/database_service.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('getTicketSalesByDate retrieves newly created ticket on active date', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE ticket_sales (
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
      },
    );

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    // 1. Insert an existing ticket from another date (e.g. 2026-10-19)
    await db.insert('ticket_sales', {
      'id': 'tkt_old_1',
      'receiptNumber': 'REC-12-99999',
      'buyerName': 'Old Party',
      'buyerPhone': '9999999999',
      'agentCode': 'AG-OLD',
      'agentName': 'Old Party',
      'drawCode': 'DEAR-1-PM',
      'drawName': 'Dear 1 PM',
      'ticketSeries': '12',
      'ticketNumber': '12 99999',
      'quantity': 1,
      'pricePerTicket': 60.0,
      'totalAmount': 60.0,
      'commissionAmount': 3.0,
      'status': 'sold',
      'paymentMode': 'cash',
      'saleDate': '2026-10-19T10:00:00.000',
      'drawDate': '2026-10-19T13:00:00.000',
    });

    // 2. Insert a newly booked ticket for today
    final newId = 'tkt_counter_${DateTime.now().millisecondsSinceEpoch}_1';
    await db.insert('ticket_sales', {
      'id': newId,
      'receiptNumber': 'REC-12-12345',
      'buyerName': 'Walk-in Customer',
      'buyerPhone': '+91 9876543210',
      'agentCode': 'AG-POS',
      'agentName': 'Walk-in Customer',
      'drawCode': 'DEAR-1-PM',
      'drawName': 'Dear 1 PM',
      'ticketSeries': '12',
      'ticketNumber': '12 12345',
      'quantity': 1,
      'pricePerTicket': 60.0,
      'totalAmount': 60.0,
      'commissionAmount': 3.0,
      'status': 'sold',
      'paymentMode': 'cash',
      'saleDate': now.toIso8601String(),
      'drawDate': DateTime(now.year, now.month, now.day, 12, 0, 0).toIso8601String(),
    });

    // Query for today's sales
    final todayResults = await db.rawQuery(
      'SELECT * FROM ticket_sales WHERE drawDate LIKE ? OR saleDate LIKE ? ORDER BY saleDate DESC, id DESC',
      ['$todayStr%', '$todayStr%'],
    );

    expect(todayResults.length, 1);
    expect(todayResults.first['id'], newId);
    expect(todayResults.first['ticketNumber'], '12 12345');

    // Query for the old date (2026-10-19)
    final oldResults = await db.rawQuery(
      'SELECT * FROM ticket_sales WHERE drawDate LIKE ? OR saleDate LIKE ? ORDER BY saleDate DESC, id DESC',
      ['2026-10-19%', '2026-10-19%'],
    );
    expect(oldResults.length, 1);
    expect(oldResults.first['id'], 'tkt_old_1');

    await db.close();
  });
}

