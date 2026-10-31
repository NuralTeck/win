import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double getRssMb() => ProcessInfo.currentRss / (1024 * 1024);
  double getMaxRssMb() => ProcessInfo.maxRss / (1024 * 1024);

  LotterySambadResultModel createBenchmarkResult() {
    return LotterySambadResultModel(
      drawId: 'audit_draw_001',
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

  List<TicketSaleModel> generateDistinctTickets(int count, int seedOffset) {
    final now = DateTime.now();
    final drawDate = DateTime(2026, 10, 29, 13, 0);

    return List.generate(count, (i) {
      final globalIdx = seedOffset + i;
      final tktNum = (10000 + (globalIdx % 90000)).toString();
      final series = (10 + (globalIdx % 80)).toString();
      return TicketSaleModel(
        id: 'tkt_${globalIdx}',
        receiptNumber: 'REC-$series-$tktNum',
        buyerName: 'Customer ${globalIdx % 50}',
        buyerPhone: '+91 9876543210',
        agentCode: 'AG-AUDIT',
        agentName: 'Seller ${globalIdx % 20}',
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

  test('3-RUN VARIANCE & TIMING AUDIT: Pure Matching vs Object Allocation', () async {
    print('\n' + '=' * 80);
    print('🔬 INDEPENDENT BENCHMARK AUDIT: TIMING BOUNDARIES & RUN VARIANCE');
    print('=' * 80);

    const int ticketsPerRun = 1000000; // 10 Lakh per run (1 Million)
    const int chunkSize = 100000;     // 100k chunks
    const int runs = 3;
    final result = createBenchmarkResult();

    final runAllocationTimesMs = <int>[];
    final runVerificationTimesMs = <int>[];
    final runTotalTimesMs = <int>[];
    final runThroughputs = <double>[];
    final runPeakMemories = <double>[];

    for (int run = 1; run <= runs; run++) {
      print('\n[RUN $run of $runs] Processing 1,000,000 distinct tickets...');
      final swTotal = Stopwatch()..start();
      int allocTimeTotal = 0;
      int verifyTimeTotal = 0;
      int winnersCount = 0;
      double peakMemThisRun = getRssMb();

      for (int c = 0; c < 10; c++) {
        // Measure object allocation time strictly
        final swAlloc = Stopwatch()..start();
        final chunkTickets = generateDistinctTickets(chunkSize, (run * 1000000) + (c * chunkSize));
        swAlloc.stop();
        allocTimeTotal += swAlloc.elapsedMilliseconds;

        // Measure pure verification matching algorithm strictly
        final swVerify = Stopwatch()..start();
        final chunkWinners = WinnerVerificationEngine.verifyWinners(
          result: result,
          soldTickets: chunkTickets,
        );
        swVerify.stop();
        verifyTimeTotal += swVerify.elapsedMilliseconds;
        winnersCount += chunkWinners.length;

        final currentMem = getRssMb();
        if (currentMem > peakMemThisRun) peakMemThisRun = currentMem;
      }

      swTotal.stop();
      final totalMs = swTotal.elapsedMilliseconds;
      final verifySpeed = (ticketsPerRun / (verifyTimeTotal / 1000));

      runAllocationTimesMs.add(allocTimeTotal);
      runVerificationTimesMs.add(verifyTimeTotal);
      runTotalTimesMs.add(totalMs);
      runThroughputs.add(verifySpeed);
      runPeakMemories.add(peakMemThisRun);

      print('  • Allocation Time:          $allocTimeTotal ms');
      print('  • Pure Verification Time:   $verifyTimeTotal ms');
      print('  • Total Chunk Loop Time:    $totalMs ms');
      print('  • Pure Matching Speed:      ${verifySpeed.toStringAsFixed(0)} tickets/sec');
      print('  • Peak RSS Memory:          ${peakMemThisRun.toStringAsFixed(2)} MB');
      print('  • Winners Verified:         $winnersCount claims');
    }

    // Calculate Variance and Medians
    runThroughputs.sort();
    final medianThroughput = runThroughputs[1];
    final variance = ((runThroughputs.last - runThroughputs.first) / medianThroughput) * 100;

    print('\n' + '=' * 80);
    print('📊 MULTI-RUN AUDIT SUMMARY');
    print('=' * 80);
    print('• Median Pure Verification Speed: ${medianThroughput.toStringAsFixed(0)} tickets / sec');
    print('• Throughput Range:               ${runThroughputs.first.toStringAsFixed(0)} — ${runThroughputs.last.toStringAsFixed(0)} tickets/sec');
    print('• Run-to-Run Variance:            ${variance.toStringAsFixed(2)}%');
    print('• Allocation Overhead Ratio:      ~${((runAllocationTimesMs[1] / runTotalTimesMs[1]) * 100).toStringAsFixed(1)}% of total loop time');
    print('• Peak RSS Memory Across Runs:    ${runPeakMemories.reduce((a, b) => a > b ? a : b).toStringAsFixed(2)} MB');
    print('• All-Time Process Max RSS:       ${getMaxRssMb().toStringAsFixed(2)} MB');
    print('=' * 80 + '\n');

    expect(medianThroughput, greaterThan(150000));
  });
}
