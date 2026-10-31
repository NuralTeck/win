import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opscore_pro/core/database/database_service.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';
import 'package:opscore_pro/features/operations/models/winning_claim_model.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late Database db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pagination_bench_');
    dbPath = p.join(tempDir.path, 'pagination_test.db');
    db = await databaseFactory.openDatabase(dbPath);

    await db.execute('PRAGMA journal_mode=WAL;');
    await db.execute('PRAGMA synchronous=NORMAL;');
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
      );
    ''');
    await db.execute('''
      CREATE TABLE winning_claims (
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
    await db.execute('CREATE INDEX idx_ticket_sales_drawDate ON ticket_sales(drawDate);');
    await db.execute('CREATE INDEX idx_ticket_sales_saleDate ON ticket_sales(saleDate);');
    await db.execute('CREATE INDEX idx_winning_claims_drawId ON winning_claims(drawId);');
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  group('Sales Pagination & Data Integrity Tests', () {
    test('1. Deterministic Ordering with Unique ID Tie-Breaker (No Skips, No Duplicates Across Pages)', () async {
      final fixedTimestamp = DateTime(2026, 10, 29, 10, 0, 0).toIso8601String();
      const int batchCount = 150;

      // Insert 150 records sharing the EXACT same saleDate timestamp
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < batchCount; i++) {
          final padId = i.toString().padLeft(4, '0');
          batch.insert('ticket_sales', {
            'id': 'tkt_tie_$padId',
            'receiptNumber': 'REC-$padId',
            'buyerName': 'Tie Buyer $i',
            'buyerPhone': '9876543210',
            'agentCode': 'AG-1',
            'agentName': 'Agent Rajiv',
            'drawCode': 'DEAR-1-PM',
            'drawName': 'Dear 1 PM',
            'ticketSeries': '12',
            'ticketNumber': '12 54321',
            'quantity': 1,
            'pricePerTicket': 6.0,
            'totalAmount': 6.0,
            'commissionAmount': 0.3,
            'status': 'sold',
            'paymentMode': 'cash',
            'saleDate': fixedTimestamp,
            'drawDate': fixedTimestamp,
          });
        }
        await batch.commit(noResult: true);
      });

      // Query page 0 (items 0..49), page 1 (items 50..99), page 2 (items 100..149)
      const pageSize = 50;
      final page0 = await db.query(
        'ticket_sales',
        orderBy: 'saleDate DESC, id DESC',
        limit: pageSize,
        offset: 0,
      );
      final page1 = await db.query(
        'ticket_sales',
        orderBy: 'saleDate DESC, id DESC',
        limit: pageSize,
        offset: pageSize,
      );
      final page2 = await db.query(
        'ticket_sales',
        orderBy: 'saleDate DESC, id DESC',
        limit: pageSize,
        offset: pageSize * 2,
      );

      expect(page0.length, equals(pageSize));
      expect(page1.length, equals(pageSize));
      expect(page2.length, equals(pageSize));

      final ids0 = page0.map((r) => r['id'] as String).toSet();
      final ids1 = page1.map((r) => r['id'] as String).toSet();
      final ids2 = page2.map((r) => r['id'] as String).toSet();

      // Ensure zero overlap across pages
      expect(ids0.intersection(ids1), isEmpty, reason: 'Page 0 and Page 1 must not share records');
      expect(ids1.intersection(ids2), isEmpty, reason: 'Page 1 and Page 2 must not share records');
      expect(ids0.intersection(ids2), isEmpty, reason: 'Page 0 and Page 2 must not share records');

      // Total distinct records retrieved equals 150
      final allRetrieved = {...ids0, ...ids1, ...ids2};
      expect(allRetrieved.length, equals(batchCount), reason: 'Zero skipped records across pages');

      // Verify strict descending tie-breaker order (id DESC)
      final allList = [...page0, ...page1, ...page2];
      for (int i = 0; i < allList.length - 1; i++) {
        final currentId = allList[i]['id'] as String;
        final nextId = allList[i + 1]['id'] as String;
        expect(currentId.compareTo(nextId) > 0, isTrue,
            reason: 'IDs must be in strict descending order ($currentId > $nextId)');
      }
    });

    test('2. >50,000 Records Across Pages Without Silent Truncation', () async {
      const int totalRows = 52000;
      final drawDate = DateTime(2026, 10, 29, 13, 0);

      // Fast batch insert of 52,000 rows
      const int chunkSize = 10000;
      for (int chunkStart = 0; chunkStart < totalRows; chunkStart += chunkSize) {
        final chunkEnd = (chunkStart + chunkSize < totalRows) ? chunkStart + chunkSize : totalRows;
        await db.transaction((txn) async {
          final batch = txn.batch();
          for (int i = chunkStart; i < chunkEnd; i++) {
            final padId = i.toString().padLeft(6, '0');
            final numStr = (10000 + (i % 90000)).toString();
            batch.insert('ticket_sales', {
              'id': 'tkt_50k_$padId',
              'receiptNumber': 'REC-$padId',
              'buyerName': i == 51500 ? 'DeepBoundaryBuyer' : 'Buyer ${i % 50}',
              'buyerPhone': '9876543210',
              'agentCode': 'AG-1',
              'agentName': 'Agent Rajiv',
              'drawCode': 'DEAR-1-PM',
              'drawName': 'Dear 1 PM',
              'ticketSeries': '12',
              'ticketNumber': '12 $numStr',
              'quantity': 1,
              'pricePerTicket': 6.0,
              'totalAmount': 6.0,
              'commissionAmount': 0.3,
              'status': 'sold',
              'paymentMode': 'cash',
              'saleDate': drawDate.add(Duration(seconds: i % 86400)).toIso8601String(),
              'drawDate': drawDate.toIso8601String(),
            });
          }
          await batch.commit(noResult: true);
        });
      }

      // Verify total count in DB exceeds 50,000
      final countRes = await db.rawQuery('SELECT COUNT(*) as cnt FROM ticket_sales');
      final totalInDb = (countRes.first['cnt'] as num).toInt();
      expect(totalInDb, equals(totalRows));

      // Query beyond 50,000 threshold (offset 51,000, limit 500)
      final deepRows = await db.query(
        'ticket_sales',
        orderBy: 'saleDate DESC, id DESC',
        limit: 500,
        offset: 51000,
      );

      expect(deepRows.length, equals(500), reason: 'Records past 50,000 must be fully accessible');

      // Verify deep record search works
      final searchRows = await db.query(
        'ticket_sales',
        where: 'buyerName = ?',
        whereArgs: ['DeepBoundaryBuyer'],
      );
      expect(searchRows.length, equals(1));
      expect(searchRows.first['id'], equals('tkt_50k_051500'));
    });

    test('3. Full Batch Winner Verification Streams All Draw Tickets (Decoupled from UI Page Size)', () async {
      const int drawTicketsCount = 5000;
      final drawDate = DateTime(2026, 10, 29, 13, 0);

      // Seed draw tickets with 5 guaranteed winning tickets placed at various indexes
      final winningIndices = {10, 500, 1500, 3000, 4800};
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (int i = 0; i < drawTicketsCount; i++) {
          final isWinner = winningIndices.contains(i);
          final numStr = isWinner ? '54321' : (10000 + (i % 89999)).toString();
          batch.insert('ticket_sales', {
            'id': 'tkt_stream_$i',
            'receiptNumber': 'REC-STR-$i',
            'buyerName': isWinner ? 'Lucky Winner $i' : 'Customer $i',
            'buyerPhone': '9876543210',
            'agentCode': 'AG-1',
            'agentName': 'Agent Rajiv',
            'drawCode': 'DEAR-1-PM',
            'drawName': 'Dear 1 PM',
            'ticketSeries': '12',
            'ticketNumber': '12 $numStr',
            'quantity': 1,
            'pricePerTicket': 6.0,
            'totalAmount': 6.0,
            'commissionAmount': 0.3,
            'status': 'sold',
            'paymentMode': 'cash',
            'saleDate': drawDate.toIso8601String(),
            'drawDate': drawDate.toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      });

      final result = LotterySambadResultModel(
        drawId: 'stream_draw_001',
        drawName: 'Dear 1 PM',
        drawDateStr: '29/10/2026',
        drawTimeStr: '1:00 PM',
        firstPrize: '54321',
        consolationPrize: '54321',
        secondPrizeNumbers: [],
        thirdPrizeNumbers: [],
        fourthPrizeNumbers: [],
        fifthPrizeNumbers: [],
        publishedAt: DateTime.now(),
      );

      // Stream draw tickets in bounded batches of 1,000 (simulating large dataset chunking)
      int offset = 0;
      const batchSize = 1000;
      final allStreamedClaims = <WinningClaimModel>[];
      int totalTicketsStreamed = 0;

      while (true) {
        final rows = await db.query(
          'ticket_sales',
          where: 'drawDate LIKE ? AND drawName = ?',
          whereArgs: ['%2026-10-29%', 'Dear 1 PM'],
          orderBy: 'saleDate DESC, id DESC',
          limit: batchSize,
          offset: offset,
        );

        if (rows.isEmpty) break;
        totalTicketsStreamed += rows.length;

        final chunk = rows.map((r) => TicketSaleModel(
          id: r['id'] as String,
          receiptNumber: r['receiptNumber'] as String,
          buyerName: r['buyerName'] as String,
          buyerPhone: r['buyerPhone'] as String,
          agentCode: r['agentCode'] as String,
          agentName: r['agentName'] as String,
          drawCode: r['drawCode'] as String,
          drawName: r['drawName'] as String,
          ticketSeries: r['ticketSeries'] as String,
          ticketNumber: r['ticketNumber'] as String,
          quantity: r['quantity'] as int,
          pricePerTicket: r['pricePerTicket'] as double,
          totalAmount: r['totalAmount'] as double,
          commissionAmount: r['commissionAmount'] as double,
          status: TicketStatus.sold,
          paymentMode: PaymentMode.cash,
          saleDate: DateTime.parse(r['saleDate'] as String),
          drawDate: DateTime.parse(r['drawDate'] as String),
        )).toList();

        final chunkClaims = await WinnerVerificationEngine.verifyWinnersAsync(
          result: result,
          soldTickets: chunk,
        );
        allStreamedClaims.addAll(chunkClaims);

        if (rows.length < batchSize) break;
        offset += rows.length;
      }

      // Assert that 100% of tickets were evaluated across the batches
      expect(totalTicketsStreamed, equals(drawTicketsCount));
      // Assert that all 5 winners placed across different chunks were discovered
      expect(allStreamedClaims.length, equals(5));
      final winnerNames = allStreamedClaims.map((c) => c.buyerName).toSet();
      expect(winnerNames, containsAll([
        'Lucky Winner 10',
        'Lucky Winner 500',
        'Lucky Winner 1500',
        'Lucky Winner 3000',
        'Lucky Winner 4800',
      ]));
    });

    test('4. Idempotent Claim Persistence: Zero Duplicate Records on Retry', () async {
      final now = DateTime.now();
      final claims = [
        WinningClaimModel(
          id: 'win_draw001_tkt100',
          drawId: 'draw001',
          drawName: 'Dear 1 PM',
          drawDate: '29/10/2026',
          drawTime: '1:00 PM',
          prizeTier: '1st Prize',
          winningNumber: '54321',
          prizeAmount: 100000.0,
          seriesCount: 12,
          baseAmount: 100000.0,
          superBonus: 0.0,
          specialIncentive: 0.0,
          buyerName: 'Winner Alpha',
          sellerName: 'Rajiv',
          ticketSeries: '12',
          ticketNumber: '54321',
          verifiedAt: now,
        ),
        WinningClaimModel(
          id: 'win_draw001_tkt101',
          drawId: 'draw001',
          drawName: 'Dear 1 PM',
          drawDate: '29/10/2026',
          drawTime: '1:00 PM',
          prizeTier: '2nd Prize',
          winningNumber: '12345',
          prizeAmount: 9000.0,
          seriesCount: 12,
          baseAmount: 9000.0,
          superBonus: 0.0,
          specialIncentive: 0.0,
          buyerName: 'Winner Beta',
          sellerName: 'Rajiv',
          ticketSeries: '12',
          ticketNumber: '12345',
          verifiedAt: now,
        ),
      ];

      // Initial save
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final c in claims) {
          batch.insert('winning_claims', {
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
            'isClaimed': 0,
            'verifiedAt': c.verifiedAt.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });

      final count1 = (await db.rawQuery('SELECT COUNT(*) as cnt FROM winning_claims')).first['cnt'] as int;
      expect(count1, equals(2));

      // Retry 1: Run identical save again
      await db.transaction((txn) async {
        final batch = txn.batch();
        for (final c in claims) {
          batch.insert('winning_claims', {
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
            'isClaimed': 0,
            'verifiedAt': c.verifiedAt.toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      });

      final count2 = (await db.rawQuery('SELECT COUNT(*) as cnt FROM winning_claims')).first['cnt'] as int;
      expect(count2, equals(2), reason: 'Count must remain exactly 2 after first retry');

      // Retry 2: Update prize amount on existing claim
      final updatedClaim = WinningClaimModel(
        id: 'win_draw001_tkt100',
        drawId: 'draw001',
        drawName: 'Dear 1 PM',
        drawDate: '29/10/2026',
        drawTime: '1:00 PM',
        prizeTier: '1st Prize',
        winningNumber: '54321',
        prizeAmount: 120000.0, // updated
        seriesCount: 12,
        baseAmount: 120000.0,
        superBonus: 0.0,
        specialIncentive: 0.0,
        buyerName: 'Winner Alpha Updated',
        sellerName: 'Rajiv',
        ticketSeries: '12',
        ticketNumber: '54321',
        verifiedAt: now,
      );

      await db.insert('winning_claims', {
        'id': updatedClaim.id,
        'drawId': updatedClaim.drawId,
        'drawName': updatedClaim.drawName,
        'drawDate': updatedClaim.drawDate,
        'drawTime': updatedClaim.drawTime,
        'prizeTier': updatedClaim.prizeTier,
        'winningNumber': updatedClaim.winningNumber,
        'prizeAmount': updatedClaim.prizeAmount,
        'seriesCount': updatedClaim.seriesCount,
        'baseAmount': updatedClaim.baseAmount,
        'superBonus': updatedClaim.superBonus,
        'specialIncentive': updatedClaim.specialIncentive,
        'buyerName': updatedClaim.buyerName,
        'sellerName': updatedClaim.sellerName,
        'ticketSeries': updatedClaim.ticketSeries,
        'ticketNumber': updatedClaim.ticketNumber,
        'isClaimed': 0,
        'verifiedAt': updatedClaim.verifiedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final count3 = (await db.rawQuery('SELECT COUNT(*) as cnt FROM winning_claims')).first['cnt'] as int;
      expect(count3, equals(2), reason: 'ConflictAlgorithm.replace must update in place without creating new row');

      final row = await db.query('winning_claims', where: 'id = ?', whereArgs: ['win_draw001_tkt100']);
      expect(row.first['prizeAmount'], equals(120000.0));
      expect(row.first['buyerName'], equals('Winner Alpha Updated'));
    });
  });
}
