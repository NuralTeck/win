import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/core/process/widgets/process_status_pill.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  testWidgets('MEASURE UI FRAME TIMINGS & JANK DURING HEAVY COMPUTATION', (WidgetTester tester) async {
    print('\n' + '=' * 80);
    print('🖥️ FLUTTER UI FRAME TIMING & RASTER JANK PROFILING');
    print('=' * 80);

    final recordedTimings = <FrameTiming>[];
    void onTimings(List<FrameTiming> timings) {
      recordedTimings.addAll(timings);
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProcessStatusPill(),
          ),
        ),
      ),
    );

    // Warm-up frames
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final drawResult = LotterySambadResultModel(
      drawId: 'frame_draw',
      drawName: 'Dear 1 PM',
      drawDateStr: '29/10/2026',
      drawTimeStr: '1:00 PM',
      firstPrize: '54321',
      consolationPrize: '54321',
      secondPrizeNumbers: ['12345', '67890'],
      thirdPrizeNumbers: ['4321', '8765'],
      fourthPrizeNumbers: ['1122', '3344'],
      fifthPrizeNumbers: ['1000', '2000'],
      publishedAt: DateTime.now(),
    );

    // Generate 10,000 tickets
    final now = DateTime.now();
    final tickets = List.generate(10000, (i) => TicketSaleModel(
      id: 'tkt_$i',
      receiptNumber: 'REC-12-$i',
      buyerName: 'Buyer',
      buyerPhone: '',
      agentCode: 'AG',
      agentName: 'Agent',
      drawCode: 'DEAR-1-PM',
      drawName: 'Dear 1 PM',
      ticketSeries: '12',
      ticketNumber: '12 ${(10000 + (i % 90000)).toString()}',
      quantity: 1,
      pricePerTicket: 6.0,
      totalAmount: 6.0,
      commissionAmount: 0.3,
      status: TicketStatus.sold,
      paymentMode: PaymentMode.cash,
      saleDate: now,
      drawDate: DateTime(2026, 10, 29, 13, 0),
    ));

    // Execute async verification on worker isolate while pumping UI frames
    final asyncWork = WinnerVerificationEngine.verifyWinnersAsync(
      result: drawResult,
      soldTickets: tickets,
    );

    int activeFramesPumped = 0;
    while (true) {
      bool isFinished = false;
      asyncWork.then((_) => isFinished = true);
      await tester.pump(const Duration(milliseconds: 16)); // Target 60 FPS (16.6 ms)
      activeFramesPumped++;
      if (isFinished || activeFramesPumped > 30) break;
    }

    final claims = await asyncWork;

    SchedulerBinding.instance.removeTimingsCallback(onTimings);

    // Analyze recorded frame durations
    int totalFrames = recordedTimings.length;
    int jankyFrames = 0;
    double maxBuildMs = 0;
    double maxRasterMs = 0;
    double totalBuildMs = 0;

    for (final t in recordedTimings) {
      final buildMs = t.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = t.rasterDuration.inMicroseconds / 1000.0;
      final totalSpanMs = t.totalSpan.inMicroseconds / 1000.0;

      if (buildMs > maxBuildMs) maxBuildMs = buildMs;
      if (rasterMs > maxRasterMs) maxRasterMs = rasterMs;
      totalBuildMs += buildMs;

      // Frame dropped / jank threshold is > 16.67 ms (below 60 FPS)
      if (totalSpanMs > 16.67) {
        jankyFrames++;
      }
    }

    final avgBuildMs = totalFrames > 0 ? (totalBuildMs / totalFrames) : 0.0;
    final jankPercentage = totalFrames > 0 ? ((jankyFrames / totalFrames) * 100) : 0.0;

    print('• Total Recorded UI Frames:    $totalFrames frames');
    print('• Active Frames Pumped:        $activeFramesPumped frames');
    print('• Average Widget Build Time:   ${avgBuildMs.toStringAsFixed(2)} ms');
    print('• Max Widget Build Time:       ${maxBuildMs.toStringAsFixed(2)} ms');
    print('• Max Raster Duration:         ${maxRasterMs.toStringAsFixed(2)} ms');
    print('• Janky / Dropped Frames (>16.6ms): $jankyFrames of $totalFrames (${jankPercentage.toStringAsFixed(1)}%)');
    print('• Verified Claims Returned:    ${claims.length} claims');
    print('=' * 80 + '\n');
  });
}

