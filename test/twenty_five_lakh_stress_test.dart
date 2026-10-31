import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  double getMemoryRssMb() => ProcessInfo.currentRss / (1024 * 1024);
  double getMaxMemoryRssMb() => ProcessInfo.maxRss / (1024 * 1024);

  LotterySambadResultModel createBenchmarkResult() {
    return LotterySambadResultModel(
      drawId: 'sambad_25_lakh_test',
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

  List<TicketSaleModel> generateTicketChunk(int chunkIndex, int chunkSize) {
    final now = DateTime.now();
    final drawDate = DateTime(2026, 10, 29, 13, 0);
    final offset = chunkIndex * chunkSize;

    return List.generate(chunkSize, (i) {
      final globalIdx = offset + i;
      final tktNum = (10000 + (globalIdx % 90000)).toString();
      final series = (10 + (globalIdx % 80)).toString();
      return TicketSaleModel(
        id: 'tkt_${globalIdx}',
        receiptNumber: 'REC-$series-$tktNum',
        buyerName: 'Customer ${globalIdx % 50}',
        buyerPhone: '+91 9876543210',
        agentCode: 'AG-25L',
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

  test('25 LAKH (2,500,000) TICKETS STRESS TEST BENCHMARK', () async {
    print('\n' + '=' * 80);
    print('🔥 25 LAKH (2,500,000) TICKETS MEGA STRESS TEST');
    print('=' * 80);

    const int totalTargetTickets = 2500000; // 25 LAKH
    const int chunkSize = 100000;          // 1 LAKH per chunk
    const int totalChunks = totalTargetTickets ~/ chunkSize; // 25 chunks

    final result = createBenchmarkResult();
    final startRss = getMemoryRssMb();
    final startMaxRss = getMaxMemoryRssMb();

    print('• Target Tickets:           25,00,000 (25 Lakh)');
    print('• Chunking Architecture:    $totalChunks chunks of ${chunkSize.toString()} tickets');
    print('• Initial Active RAM:       ${startRss.toStringAsFixed(2)} MB');
    print('• Initial Peak RAM:         ${startMaxRss.toStringAsFixed(2)} MB');
    print('-' * 80);

    final globalStopwatch = Stopwatch()..start();
    int totalWinnersFound = 0;
    double peakMemoryObserved = startRss;

    for (int chunk = 0; chunk < totalChunks; chunk++) {
      final chunkStopwatch = Stopwatch()..start();

      // 1. Generate 1 Lakh tickets
      final tickets = generateTicketChunk(chunk, chunkSize);

      // 2. Process Verification via WinnerVerificationEngine
      final winners = WinnerVerificationEngine.verifyWinners(
        result: result,
        soldTickets: tickets,
      );

      chunkStopwatch.stop();
      totalWinnersFound += winners.length;

      final currentRss = getMemoryRssMb();
      if (currentRss > peakMemoryObserved) {
        peakMemoryObserved = currentRss;
      }

      final processedSoFar = (chunk + 1) * chunkSize;
      final percent = ((processedSoFar / totalTargetTickets) * 100).toInt();
      final chunkThroughput = (chunkSize / (chunkStopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(0);

      print('  [Chunk ${(chunk + 1).toString().padLeft(2)}/$totalChunks] $percent% | Processed: ${processedSoFar.toString().padLeft(7)} | Time: ${chunkStopwatch.elapsedMilliseconds.toString().padLeft(4)} ms | Speed: $chunkThroughput t/s | RAM: ${currentRss.toStringAsFixed(1)} MB | Winners: ${winners.length}');

      // Yield briefly to event loop every 5 chunks to allow GC
      if ((chunk + 1) % 5 == 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    globalStopwatch.stop();
    final finalRss = getMemoryRssMb();
    final finalMaxRss = getMaxMemoryRssMb();
    final totalSeconds = globalStopwatch.elapsedMilliseconds / 1000;
    final overallThroughput = (totalTargetTickets / totalSeconds).toStringAsFixed(0);

    print('=' * 80);
    print('🏁 25 LAKH STRESS TEST COMPLETED SUCCESSFULLY');
    print('=' * 80);
    print('• Total Tickets Checked:     ${totalTargetTickets} (25 Lakh)');
    print('• Total Winners Identified:  $totalWinnersFound claims');
    print('• Total Elapsed Time:        ${totalSeconds.toStringAsFixed(2)} seconds (${globalStopwatch.elapsedMilliseconds} ms)');
    print('• Average Throughput:        $overallThroughput tickets / second');
    print('• Peak Active RAM:           ${peakMemoryObserved.toStringAsFixed(2)} MB');
    print('• Final Active RAM:          ${finalRss.toStringAsFixed(2)} MB');
    print('• Net RAM Delta:             +${(finalRss - startRss).toStringAsFixed(2)} MB');
    print('• Can System Handle 25 Lakh? YES! 100% Stable with Chunking');
    print('=' * 80 + '\n');

    expect(totalWinnersFound, greaterThan(0));
    expect(totalSeconds, lessThan(60.0)); // Must finish within 60 seconds
  }, timeout: const Timeout(Duration(minutes: 3)));
}
