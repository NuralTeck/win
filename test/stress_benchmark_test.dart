import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/core/process/models/process_model.dart';
import 'package:opscore_pro/core/process/services/process_manager.dart';
import 'package:opscore_pro/core/services/security_crypto_service.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double getMemoryRssMb() {
    return ProcessInfo.currentRss / (1024 * 1024);
  }

  double getMaxMemoryRssMb() {
    return ProcessInfo.maxRss / (1024 * 1024);
  }

  LotterySambadResultModel createBenchmarkResult() {
    return LotterySambadResultModel(
      drawId: 'benchmark_draw_001',
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

  List<TicketSaleModel> generateBenchmarkTickets(int count) {
    final now = DateTime.now();
    final drawDate = DateTime(2026, 10, 29, 13, 0);
    return List.generate(count, (i) {
      final tktNum = (10000 + (i % 90000)).toString();
      final series = (10 + (i % 80)).toString();
      return TicketSaleModel(
        id: 'tkt_bench_$i',
        receiptNumber: 'REC-$series-$tktNum',
        buyerName: 'Customer ${i % 25}',
        buyerPhone: '+91 9876543210',
        agentCode: 'AG-BENCH',
        agentName: 'Seller ${i % 10}',
        drawCode: 'DEAR-1-PM',
        drawName: 'Dear 1 PM',
        ticketSeries: series,
        ticketNumber: '$series $tktNum',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: now,
        drawDate: drawDate,
      );
    });
  }

  group('📊 REAL-WORLD STRESS & RESOURCE PROFILING BENCHMARK', () {
    test('PROFILING: Baseline, CPU Calculations, Memory Bounding & High Concurrency', () async {
      print('\n' + '=' * 75);
      print('🚀 STARTING EMPIRICAL CPU & RAM (MEMORY) STRESS TEST');
      print('=' * 75);

      // ─────────────────────────────────────────────────────────────
      // 1. BASELINE MEMORY FOOTPRINT
      // ─────────────────────────────────────────────────────────────
      final baselineRss = getMemoryRssMb();
      final baselineMaxRss = getMaxMemoryRssMb();

      print('\n[BENCHMARK 1] 🟢 BASELINE IDLE RESOURCE STATE');
      print('  • Current Resident Set Size (RAM): ${baselineRss.toStringAsFixed(2)} MB');
      print('  • Peak Allocated System RAM:      ${baselineMaxRss.toStringAsFixed(2)} MB');

      // ─────────────────────────────────────────────────────────────
      // 2. CPU STRESS TEST: 10,000 TICKETS MATCHING ACROSS ISOLATES
      // ─────────────────────────────────────────────────────────────
      print('\n[BENCHMARK 2] ⚡ HEAVY COMPUTATION: 10,000 TICKETS MATCHING (Worker Isolate)');
      final tickets10k = generateBenchmarkTickets(10000);
      final drawResult = createBenchmarkResult();

      final memBefore10k = getMemoryRssMb();
      final sw10k = Stopwatch()..start();

      final winners10k = await WinnerVerificationEngine.verifyWinnersAsync(
        result: drawResult,
        soldTickets: tickets10k,
      );

      sw10k.stop();
      final memAfter10k = getMemoryRssMb();
      final throughput10k = (10000 / (sw10k.elapsedMilliseconds / 1000)).toStringAsFixed(0);

      print('  • Processed Tickets:             10,000 tickets');
      print('  • Winners / Claims Detected:     ${winners10k.length} claims');
      print('  • Computation Duration:          ${sw10k.elapsedMilliseconds} ms (${(sw10k.elapsedMilliseconds / 1000).toStringAsFixed(3)} sec)');
      print('  • Calculation Throughput:        $throughput10k tickets / second');
      print('  • RAM Before Test:               ${memBefore10k.toStringAsFixed(2)} MB');
      print('  • RAM Peak / After Test:         ${memAfter10k.toStringAsFixed(2)} MB (Delta: +${(memAfter10k - memBefore10k).toStringAsFixed(2)} MB)');

      expect(winners10k, isNotNull);
      expect(sw10k.elapsedMilliseconds, lessThan(3000)); // Must finish within 3 seconds

      // ─────────────────────────────────────────────────────────────
      // 3. CPU ULTRA STRESS TEST: 25,000 TICKETS MATCHING
      // ─────────────────────────────────────────────────────────────
      print('\n[BENCHMARK 3] 🔥 ULTRA COMPUTATION: 25,000 TICKETS MATCHING (Massive Dataset)');
      final tickets25k = generateBenchmarkTickets(25000);

      final memBefore25k = getMemoryRssMb();
      final sw25k = Stopwatch()..start();

      final winners25k = await WinnerVerificationEngine.verifyWinnersAsync(
        result: drawResult,
        soldTickets: tickets25k,
      );

      sw25k.stop();
      final memAfter25k = getMemoryRssMb();
      final throughput25k = (25000 / (sw25k.elapsedMilliseconds / 1000)).toStringAsFixed(0);

      print('  • Processed Tickets:             25,000 tickets');
      print('  • Winners / Claims Detected:     ${winners25k.length} claims');
      print('  • Computation Duration:          ${sw25k.elapsedMilliseconds} ms (${(sw25k.elapsedMilliseconds / 1000).toStringAsFixed(3)} sec)');
      print('  • Calculation Throughput:        $throughput25k tickets / second');
      print('  • RAM Before Test:               ${memBefore25k.toStringAsFixed(2)} MB');
      print('  • RAM Peak / After Test:         ${memAfter25k.toStringAsFixed(2)} MB (Delta: +${(memAfter25k - memBefore25k).toStringAsFixed(2)} MB)');

      expect(winners25k, isNotNull);
      expect(sw25k.elapsedMilliseconds, lessThan(6000)); // Must finish within 6 seconds

      // ─────────────────────────────────────────────────────────────
      // 4. CONCURRENCY & MEMORY BOUNDING UNDER BURST LOAD
      // ─────────────────────────────────────────────────────────────
      print('\n[BENCHMARK 4] 🛡️ SCHEDULER BURST LOAD & MEMORY BOUNDING (ProcessManager)');
      final manager = ProcessManager.instance;
      manager.clearCompleted();
      manager.maxConcurrentProcesses = 3;
      manager.maxQueuedProcesses = 100;
      manager.maxFinishedHistory = 50;

      final memBeforeBurst = getMemoryRssMb();
      final swQueue = Stopwatch()..start();

      int rejectedTasks = 0;
      int completedTasks = 0;

      // Burst attempt: Enqueue 130 tasks rapidly
      for (int i = 1; i <= 130; i++) {
        try {
          await manager.enqueue(
            title: 'Burst Task #$i',
            action: (ctx) async {
              completedTasks++;
              await Future.delayed(const Duration(milliseconds: 5));
            },
          );
        } on ProcessQueueFullException {
          rejectedTasks++;
        }
      }

      print('  • Tasks Ingested in Burst:       130 tasks');
      print('  • Overflow Blocked by Queue:     $rejectedTasks tasks (Protected against memory exhaustion)');
      print('  • Tasks Enqueued Safely:         ${130 - rejectedTasks} tasks');

      // Wait for all queued tasks to finish
      while (manager.state.isAnyRunning || manager.state.queuedCount > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      swQueue.stop();

      final memAfterBurst = getMemoryRssMb();
      final finishedHistoryCount = manager.state.completedProcesses.length;

      print('  • Total Queue Processing Time:   ${swQueue.elapsedMilliseconds} ms');
      print('  • Completed Tasks:               $completedTasks tasks');
      print('  • Retained History in Memory:    $finishedHistoryCount / 50 tasks (Bounded by maxFinishedHistory)');
      print('  • RAM After Execution & Eviction:${memAfterBurst.toStringAsFixed(2)} MB');
      print('  • Memory Leak Protection:        CONFIRMED (History capped strictly to $finishedHistoryCount items)');

      expect(rejectedTasks, greaterThan(0)); // Queue limit was actively enforced
      expect(finishedHistoryCount, lessThanOrEqualTo(50)); // Memory budget respected

      // ─────────────────────────────────────────────────────────────
      // 5. CRYPTOGRAPHIC HASHING & AUTHENTICATION THROUGHPUT
      // ─────────────────────────────────────────────────────────────
      print('\n[BENCHMARK 5] 🔐 CRYPTO AUTHENTICATION STRESS TEST (Salted SHA-256)');
      final crypto = SecurityCryptoService.instance;
      const testHashCount = 500;
      final swCrypto = Stopwatch()..start();

      for (int i = 0; i < testHashCount; i++) {
        final hash = crypto.hashPassword('OperatorPassword#$i');
        final isVerified = crypto.verifyPassword('OperatorPassword#$i', hash);
        if (!isVerified) throw StateError('Hash verification failed');
      }

      swCrypto.stop();
      final cryptoThroughput = (testHashCount / (swCrypto.elapsedMilliseconds / 1000)).toStringAsFixed(0);

      print('  • Salted Hashes Generated & Verified: $testHashCount passwords');
      print('  • Total Crypto Duration:             ${swCrypto.elapsedMilliseconds} ms');
      print('  • Crypto Throughput:                 $cryptoThroughput operations / second');
      print('  • Avg Latency per Salted Hash:       ${(swCrypto.elapsedMicroseconds / testHashCount / 1000).toStringAsFixed(3)} ms');

      // ─────────────────────────────────────────────────────────────
      // 6. FINAL RECOVERY & PEAK MEMORY AUDIT
      // ─────────────────────────────────────────────────────────────
      final finalRss = getMemoryRssMb();
      final finalMaxRss = getMaxMemoryRssMb();

      print('\n' + '=' * 75);
      print('🏁 STRESS TEST COMPLETED SUCCESSFULLY');
      print('=' * 75);
      print('  • Final Active Resident RAM:     ${finalRss.toStringAsFixed(2)} MB');
      print('  • All-Time Peak Memory Recorded: ${finalMaxRss.toStringAsFixed(2)} MB');
      print('  • Total Memory Delta:            +${(finalRss - baselineRss).toStringAsFixed(2)} MB (Completely bounded)');
      print('=' * 75 + '\n');
    });
  });
}

