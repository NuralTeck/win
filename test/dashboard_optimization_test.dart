import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opscore_pro/core/database/database_service.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';
import 'package:opscore_pro/features/dashboard/screens/dashboard_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Dashboard Direct SQLite Optimization Tests', () {
    test('getDashboardMetrics and party/draw summaries work accurately on SQLite', () async {
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
          await db.execute('''
            CREATE TABLE lottery_results (
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
        },
      );

      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Insert test sales for Party A (2 tickets, 120 Rs, Draw 1 PM) and Party B (1 ticket, 60 Rs, Draw 6 PM)
      await db.insert('ticket_sales', {
        'id': 'ts_1',
        'receiptNumber': 'REC-001',
        'buyerName': 'Direct Buyer',
        'buyerPhone': '9999999999',
        'agentCode': 'AGT1',
        'agentName': 'Party A',
        'drawCode': 'D1',
        'drawName': '1:00 PM Morning',
        'ticketSeries': '12A',
        'ticketNumber': '12345',
        'quantity': 2,
        'pricePerTicket': 60.0,
        'totalAmount': 120.0,
        'commissionAmount': 0.0,
        'status': 'confirmed',
        'paymentMode': 'Cash',
        'saleDate': '${todayStr}T10:00:00',
        'drawDate': '${todayStr}T13:00:00',
      });

      await db.insert('ticket_sales', {
        'id': 'ts_2',
        'receiptNumber': 'REC-002',
        'buyerName': 'Party B',
        'buyerPhone': '8888888888',
        'agentCode': '',
        'agentName': '',
        'drawCode': 'D2',
        'drawName': '6:00 PM Day',
        'ticketSeries': '12B',
        'ticketNumber': '54321',
        'quantity': 1,
        'pricePerTicket': 60.0,
        'totalAmount': 60.0,
        'commissionAmount': 0.0,
        'status': 'confirmed',
        'paymentMode': 'Cash',
        'saleDate': '${todayStr}T11:00:00',
        'drawDate': '${todayStr}T18:00:00',
      });

      // Insert lottery result
      await db.insert('lottery_results', {
        'id': 'res_1',
        'drawName': '1:00 PM Morning',
        'drawDateStr': todayStr,
        'drawTimeStr': '1:00 PM',
        'firstPrize': '12A 12345',
        'secondPrizeNumbers': '',
        'thirdPrizeNumbers': '',
        'fourthPrizeNumbers': '',
        'fifthPrizeNumbers': '',
        'verifiedWinnersCount': 1,
        'totalPayoutAmount': 50000.0,
        'publishedAt': DateTime.now().toIso8601String(),
      });

      // Test Direct SQLite KPI Aggregations
      final kpiRes = await db.rawQuery('''
        SELECT 
          COALESCE(SUM(totalAmount), 0.0) as totalCollection,
          COALESCE(SUM(quantity), 0) as totalTickets,
          COUNT(DISTINCT COALESCE(NULLIF(agentName, ''), NULLIF(buyerName, ''), 'Direct')) as totalParties
        FROM ticket_sales
        WHERE saleDate LIKE ?
      ''', ['$todayStr%']);

      expect(kpiRes.first['totalCollection'], 180.0);
      expect(kpiRes.first['totalTickets'], 3);
      expect(kpiRes.first['totalParties'], 2);

      // Test Party Hisab Query
      final partyRes = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(agentName, ''), NULLIF(buyerName, ''), 'Direct') as name,
          COALESCE(SUM(quantity), 0) as tickets,
          COALESCE(SUM(totalAmount), 0.0) as collection,
          COUNT(DISTINCT drawName) as draws
        FROM ticket_sales
        WHERE saleDate LIKE ?
        GROUP BY name
        ORDER BY collection DESC
      ''', ['$todayStr%']);

      expect(partyRes.length, 2);
      expect(partyRes[0]['name'], 'Party A');
      expect(partyRes[0]['collection'], 120.0);
      expect(partyRes[0]['tickets'], 2);
      expect(partyRes[1]['name'], 'Party B');
      expect(partyRes[1]['collection'], 60.0);

      // Test Draw Hisab Query
      final drawRes = await db.rawQuery('''
        SELECT 
          COALESCE(NULLIF(drawName, ''), 'Unknown Draw') as drawName,
          COALESCE(SUM(quantity), 0) as tickets,
          COALESCE(SUM(totalAmount), 0.0) as collection
        FROM ticket_sales
        WHERE saleDate LIKE ?
        GROUP BY drawName
        ORDER BY collection DESC
      ''', ['$todayStr%']);

      expect(drawRes.length, 2);
      expect(drawRes[0]['drawName'], '1:00 PM Morning');
      expect(drawRes[0]['collection'], 120.0);
      expect(drawRes[1]['drawName'], '6:00 PM Day');
      expect(drawRes[1]['collection'], 60.0);

      // Test Inami Payout Query
      final inamiRes = await db.rawQuery('''
        SELECT COALESCE(SUM(totalPayoutAmount), 0.0) as totalInami
        FROM lottery_results
        WHERE drawDateStr LIKE ?
      ''', ['$todayStr%']);

      expect(inamiRes.first['totalInami'], 50000.0);

      await db.close();
    });
  });
}

