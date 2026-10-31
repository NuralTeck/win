import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/models/winning_claim_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  double getRssMb() => ProcessInfo.currentRss / (1024 * 1024);

  LotterySambadResultModel createBenchmarkResult() {
    return LotterySambadResultModel(
      drawId: 'e2e_draw_001',
      drawName: 'Dear 1 PM',
      drawDateStr: '29/10/2026',
      drawTimeStr: '1:00 PM',
      firstPrize: '54321',
      consolationPrize: '54321',
      secondPrizeNumbers: ['12345', '67890', '23456', '78901', '34567'],
      thirdPrizeNumbers: ['4321', '8765', '2109', '6543', '0987'],
      fourthPrizeNumbers: ['1122', '3344', '5566', '7788', '9900'],
      fifthPrizeNumbers: List.generate(50, (i) => (1000 + i * 150).toString()),
      publishedAt: DateTime.now(),
    );
  }

  test('END-TO-END SQLITE WORKFLOW, TIMING RECONCILIATION & ISOLATE AUDIT', () async {
    print('\n' + '=' * 80);
    print('💾 SQLITE END-TO-END WORKFLOW BENCHMARK & TIMING RECONCILIATION');
    print('=' * 80);

    final tempDir = await Directory.systemTemp.createTemp('opscore_sqlite_bench_');
    final dbPath = p.join(tempDir.path, 'e2e_bench.db');
    final db = await databaseFactory.openDatabase(dbPath);

    // Apply Production PRAGMAs & Indexes
    await db.execute('PRAGMA journal_mode=WAL;');
    await db.execute('PRAGMA synchronous=NORMAL;');
    await db.execute('''
      CREATE TABLE ticket_sales (
        id TEXT PRIMARY KEY,
        receiptNumber TEXT,
        buyerName TEXT,
        buyerPhone TEXT,
        agentCode TEXT,
        agentName TEXT,
        drawCode TEXT,
        drawName TEXT,
        ticketSeries TEXT,
        ticketNumber TEXT,
        quantity INTEGER,
        pricePerTicket REAL,
        totalAmount REAL,
        commissionAmount REAL,
        status TEXT,
        paymentMode TEXT,
        saleDate TEXT,
        drawDate TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE winning_claims (
        id TEXT PRIMARY KEY,
        drawId TEXT,
        drawName TEXT,
        drawDate TEXT,
        drawTime TEXT,
        prizeTier TEXT,
        winningNumber TEXT,
        prizeAmount REAL,
        seriesCount INTEGER,
        baseAmount REAL,
        superBonus REAL,
        specialIncentive REAL,
        buyerName TEXT,
        sellerName TEXT,
        ticketSeries TEXT,
        ticketNumber TEXT,
        isClaimed INTEGER DEFAULT 0,
        verifiedAt TEXT
      );
    ''');
    await db.execute('CREATE INDEX idx_ticket_sales_draw_series ON ticket_sales(drawDate, drawCode, ticketSeries);');
    await db.execute('CREATE INDEX idx_ticket_sales_drawDate ON ticket_sales(drawDate);');
    await db.execute('CREATE INDEX idx_ticket_sales_saleDate ON ticket_sales(saleDate);');
    await db.execute('CREATE INDEX idx_winning_claims_drawId ON winning_claims(drawId);');

    final memBefore = getRssMb();
    const int totalTickets = 10000;
    final drawDate = DateTime(2026, 10, 29, 13, 0);
    final now = DateTime.now();

    // ─────────────────────────────────────────────────────────────
    // 1. INGESTION BENCHMARK: BATCH INSERTION INTO SQLITE
    // ─────────────────────────────────────────────────────────────
    final swInsert = Stopwatch()..start();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (int i = 0; i < totalTickets; i++) {
        final tktNum = (10000 + (i % 90000)).toString();
        final series = (10 + (i % 80)).toString();
        batch.insert('ticket_sales', {
          'id': 'tkt_e2e_$i',
          'receiptNumber': 'REC-$series-$tktNum',
          'buyerName': 'Buyer ${i % 25}',
          'buyerPhone': '+91 9876543210',
          'agentCode': 'AG-1',
          'agentName': 'Agent ${i % 10}',
          'drawCode': 'DEAR-1-PM',
          'drawName': 'Dear 1 PM',
          'ticketSeries': series,
          'ticketNumber': '$series $tktNum',
          'quantity': 1,
          'pricePerTicket': 6.0,
          'totalAmount': 6.0,
          'commissionAmount': 0.3,
          'status': 'sold',
          'paymentMode': 'cash',
          'saleDate': now.toIso8601String(),
          'drawDate': drawDate.toIso8601String(),
        });
      }
      await batch.commit(noResult: true);
    });
    swInsert.stop();
    final insertRate = (totalTickets / (swInsert.elapsedMilliseconds / 1000)).toStringAsFixed(0);

    // ─────────────────────────────────────────────────────────────
    // 2. END-TO-END STEP A: INDEXED QUERY FROM SQLITE
    // ─────────────────────────────────────────────────────────────
    final swQuery = Stopwatch()..start();
    final queryRows = await db.query(
      'ticket_sales',
      where: 'drawDate LIKE ? AND drawCode = ?',
      whereArgs: ['2026-10-29%', 'DEAR-1-PM'],
      orderBy: 'saleDate DESC, id DESC',
    );
    swQuery.stop();

    // ─────────────────────────────────────────────────────────────
    // 2b. END-TO-END STEP B: MODEL DESERIALIZATION & CONVERSION
    // ─────────────────────────────────────────────────────────────
    final swModelConv = Stopwatch()..start();
    final sales = queryRows.map((r) => TicketSaleModel(
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
    swModelConv.stop();

    // ─────────────────────────────────────────────────────────────
    // 3. VERIFICATION BENCHMARK: SYNC vs COMPUTE() ISOLATE
    // ─────────────────────────────────────────────────────────────
    final result = createBenchmarkResult();

    // A. Synchronous run (baseline comparison)
    final swSync = Stopwatch()..start();
    final syncWinners = WinnerVerificationEngine.verifyWinners(result: result, soldTickets: sales);
    swSync.stop();

    // B. compute() Worker Isolate run (production standard)
    final swAsync = Stopwatch()..start();
    final asyncWinners = await WinnerVerificationEngine.verifyWinnersAsync(result: result, soldTickets: sales);
    swAsync.stop();

    final isolateOverheadMs = swAsync.elapsedMilliseconds - swSync.elapsedMilliseconds;

    // ─────────────────────────────────────────────────────────────
    // 4. END-TO-END STEP D: TRANSACTIONAL CLAIM PERSISTENCE
    // ─────────────────────────────────────────────────────────────
    final swPersist = Stopwatch()..start();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final w in asyncWinners) {
        batch.insert('winning_claims', {
          'id': w.id,
          'drawId': w.drawId,
          'drawName': w.drawName,
          'drawDate': w.drawDate,
          'drawTime': w.drawTime,
          'prizeTier': w.prizeTier,
          'winningNumber': w.winningNumber,
          'prizeAmount': w.prizeAmount,
          'seriesCount': w.seriesCount,
          'baseAmount': w.baseAmount,
          'superBonus': w.superBonus,
          'specialIncentive': w.specialIncentive,
          'buyerName': w.buyerName,
          'sellerName': w.sellerName,
          'ticketSeries': w.ticketSeries,
          'ticketNumber': w.ticketNumber,
          'isClaimed': w.isClaimed ? 1 : 0,
          'verifiedAt': w.verifiedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    swPersist.stop();

    // ─────────────────────────────────────────────────────────────
    // 5. CLAIM IDEMPOTENCY / RETRY PERSISTENCE VERIFICATION
    // ─────────────────────────────────────────────────────────────
    final resBefore = await db.rawQuery('SELECT COUNT(*) as cnt FROM winning_claims WHERE drawId = ?', [result.drawId]);
    final countBeforeRetry = (resBefore.first['cnt'] as num).toInt();

    // Repeat claim persistence (simulating retry)
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final w in asyncWinners) {
        batch.insert('winning_claims', {
          'id': w.id,
          'drawId': w.drawId,
          'drawName': w.drawName,
          'drawDate': w.drawDate,
          'drawTime': w.drawTime,
          'prizeTier': w.prizeTier,
          'winningNumber': w.winningNumber,
          'prizeAmount': w.prizeAmount,
          'seriesCount': w.seriesCount,
          'baseAmount': w.baseAmount,
          'superBonus': w.superBonus,
          'specialIncentive': w.specialIncentive,
          'buyerName': w.buyerName,
          'sellerName': w.sellerName,
          'ticketSeries': w.ticketSeries,
          'ticketNumber': w.ticketNumber,
          'isClaimed': w.isClaimed ? 1 : 0,
          'verifiedAt': w.verifiedAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });

    final resAfter = await db.rawQuery('SELECT COUNT(*) as cnt FROM winning_claims WHERE drawId = ?', [result.drawId]);
    final countAfterRetry = (resAfter.first['cnt'] as num).toInt();

    // ─────────────────────────────────────────────────────────────
    // 6. DB-LEVEL PAGINATION & TIE-BREAKER VERIFICATION
    // ─────────────────────────────────────────────────────────────
    final page0 = await db.query(
      'ticket_sales',
      orderBy: 'saleDate DESC, id DESC',
      limit: 50,
      offset: 0,
    );
    final page1 = await db.query(
      'ticket_sales',
      orderBy: 'saleDate DESC, id DESC',
      limit: 50,
      offset: 50,
    );

    final dbFile = File(dbPath);
    final dbSizeBytes = await dbFile.length();
    final memAfter = getRssMb();

    // Reconciled End-to-End Workflow Calculations
    final e2eAsyncTotalMs = swQuery.elapsedMilliseconds +
        swModelConv.elapsedMilliseconds +
        swAsync.elapsedMilliseconds +
        swPersist.elapsedMilliseconds;

    final e2eSyncTotalMs = swQuery.elapsedMilliseconds +
        swModelConv.elapsedMilliseconds +
        swSync.elapsedMilliseconds +
        swPersist.elapsedMilliseconds;

    print('\n📦 INGESTION BENCHMARK:');
    print('  • SQLite Batch Insert ($totalTickets rows):     ${swInsert.elapsedMilliseconds} ms ($insertRate rows/sec)');
    print('\n🚀 PRODUCTION END-TO-END WORKFLOW (Worker Isolate compute):');
    print('  1. Indexed Query Read (10,000 rows):    ${swQuery.elapsedMilliseconds} ms');
    print('  2. Model Conversion / Deserialization:  ${swModelConv.elapsedMilliseconds} ms');
    print('  3. compute() Worker Isolate Matching:   ${swAsync.elapsedMilliseconds} ms (Isolate overhead: ${isolateOverheadMs >= 0 ? "+" : ""}${isolateOverheadMs} ms)');
    print('  4. Transactional Claim Persistence:     ${swPersist.elapsedMilliseconds} ms (${asyncWinners.length} claims)');
    print('  -----------------------------------------------------------------');
    print('  ⚡ Total End-to-End Latency (Async Isolate): $e2eAsyncTotalMs ms');

    print('\n🔬 COMPARISON BASELINE (Direct Synchronous In-Thread Matching):');
    print('  1. Indexed Query Read:                  ${swQuery.elapsedMilliseconds} ms');
    print('  2. Model Conversion / Deserialization:  ${swModelConv.elapsedMilliseconds} ms');
    print('  3. Synchronous In-Thread Matching:      ${swSync.elapsedMilliseconds} ms');
    print('  4. Transactional Claim Persistence:     ${swPersist.elapsedMilliseconds} ms');
    print('  -----------------------------------------------------------------');
    print('  ⏱️ Total Latency (Synchronous Baseline):    $e2eSyncTotalMs ms');

    print('\n📐 TIMING RECONCILIATION AUDIT:');
    print('  • Prior Reported Total: 882 ms');
    print('  • Root Cause of 882 ms: Erroneously summed Ingestion (631ms) + Query (68ms) + Sync (101ms) + Async (76ms) + Persist (6ms) = 882 ms.');
    print('  • Reconciliation: Sync matching (101ms) and Async matching (76ms) are ALTERNATIVES, not sequential steps.');
    print('  • Real Workflow A (Async Isolate E2E): Query (${swQuery.elapsedMilliseconds}ms) + ModelConv (${swModelConv.elapsedMilliseconds}ms) + Async (${swAsync.elapsedMilliseconds}ms) + Persist (${swPersist.elapsedMilliseconds}ms) = $e2eAsyncTotalMs ms.');
    print('  • Real Workflow B (Sync Baseline E2E): Query (${swQuery.elapsedMilliseconds}ms) + ModelConv (${swModelConv.elapsedMilliseconds}ms) + Sync (${swSync.elapsedMilliseconds}ms) + Persist (${swPersist.elapsedMilliseconds}ms) = $e2eSyncTotalMs ms.');

    print('\n🛡️ RELIABILITY & CORRECTNESS:');
    print('  • Claims before retry: $countBeforeRetry | Claims after retry: $countAfterRetry');
    print('  • Duplicate claims created on retry: 0 (ConflictAlgorithm.replace idempotency verified)');
    print('  • Deterministic pagination: Page 0 (${page0.length} items, first id: ${page0.first['id']}), Page 1 (${page1.length} items, first id: ${page1.first['id']})');
    print('  • Database File Size on Disk:          ${(dbSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB');
    print('  • Process RSS Memory:                  ${memBefore.toStringAsFixed(2)} MB -> ${memAfter.toStringAsFixed(2)} MB');
    print('=' * 80 + '\n');

    expect(syncWinners.length, equals(asyncWinners.length));
    expect(queryRows.length, equals(totalTickets));
    expect(countBeforeRetry, equals(asyncWinners.length));
    expect(countAfterRetry, equals(countBeforeRetry), reason: 'Retries must not create duplicate claims');
    expect(page0.length, equals(50));
    expect(page1.length, equals(50));
    expect(page0.first['id'], isNot(equals(page1.first['id'])), reason: 'Pages must be distinct');

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
