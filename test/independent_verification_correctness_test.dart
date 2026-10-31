import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:opscore_pro/features/operations/models/lottery_sambad_result_model.dart';
import 'package:opscore_pro/features/operations/models/prize_config_model.dart';
import 'package:opscore_pro/features/operations/models/winning_claim_model.dart';
import 'package:opscore_pro/features/operations/utils/winner_verification_engine.dart';
import 'package:opscore_pro/features/shared/models/ticket_sale_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LotterySambadResultModel createKnownResult() {
    return LotterySambadResultModel(
      drawId: 'draw_test_001',
      drawName: 'Dear 1 PM',
      drawDateStr: '29/10/2026',
      drawTimeStr: '1:00 PM',
      firstPrize: '54321',
      consolationPrize: '54321',
      secondPrizeNumbers: ['11111', '22222', '33333'],
      thirdPrizeNumbers: ['4444', '5555'],
      fourthPrizeNumbers: ['6666', '7777'],
      fifthPrizeNumbers: ['8888', '9999', '4321', '5555'], // 4321 overlaps with 1st prize suffix; 5555 overlaps with 3rd prize
      publishedAt: DateTime.now(),
    );
  }

  group('INDEPENDENT CORRECTNESS & BOUNDARY VERIFICATION', () {
    test('Rule 1: 1st Prize Precedence over 5th Prize Overlap', () {
      final res = createKnownResult();
      // Ticket is 54321 (1st prize). Last 4 digits '4321' is in 5th prize list!
      final ticket = TicketSaleModel(
        id: 'tkt_1st_precedence',
        receiptNumber: 'REC-12-54321',
        buyerName: 'Ranjit',
        buyerPhone: '',
        agentCode: 'AG-1',
        agentName: 'Seller A',
        drawCode: 'DEAR-1-PM',
        drawName: 'Dear 1 PM',
        ticketSeries: '12',
        ticketNumber: '12 54321',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(2026, 10, 29, 10, 0),
        drawDate: DateTime(2026, 10, 29, 13, 0),
      );

      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: [ticket],
      );

      // Must produce exactly ONE claim (1st prize), NOT both 1st and 5th!
      expect(claims.length, equals(1));
      expect(claims.first.prizeTier, equals('🥇 1st Prize'));
    });

    test('Rule 2: 3rd Prize Precedence over 5th Prize Overlap', () {
      final res = createKnownResult();
      // 5555 is in BOTH 3rd prize and 5th prize lists!
      final ticket = TicketSaleModel(
        id: 'tkt_3rd_overlap',
        receiptNumber: 'REC-10-15555',
        buyerName: 'Amit',
        buyerPhone: '',
        agentCode: 'AG-1',
        agentName: 'Seller A',
        drawCode: 'DEAR-1-PM',
        drawName: 'Dear 1 PM',
        ticketSeries: '10',
        ticketNumber: '10 15555',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(2026, 10, 29, 10, 0),
        drawDate: DateTime(2026, 10, 29, 13, 0),
      );

      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: [ticket],
      );

      // Must produce exactly ONE claim for 3rd prize (higher payout)
      expect(claims.length, equals(1));
      expect(claims.first.prizeTier, equals('🥉 3rd Prize'));
    });

    test('Rule 3: Date Mismatch Rejection', () {
      final res = createKnownResult();
      // Ticket is for tomorrow 30/10/2026, result is for 29/10/2026
      final ticket = TicketSaleModel(
        id: 'tkt_date_mismatch',
        receiptNumber: 'REC-12-54321',
        buyerName: 'Late Buyer',
        buyerPhone: '',
        agentCode: 'AG-1',
        agentName: 'Seller A',
        drawCode: 'DEAR-1-PM',
        drawName: 'Dear 1 PM',
        ticketSeries: '12',
        ticketNumber: '12 54321',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(2026, 10, 30, 10, 0),
        drawDate: DateTime(2026, 10, 30, 13, 0),
      );

      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: [ticket],
      );

      // Must reject due to date mismatch
      expect(claims, isEmpty);
    });

    test('Rule 4: Shift / Draw Time Mismatch Rejection', () {
      final res = createKnownResult(); // Result is 'Dear 1 PM'
      // Ticket is for 'Dear 8 PM'
      final ticket = TicketSaleModel(
        id: 'tkt_shift_mismatch',
        receiptNumber: 'REC-12-54321',
        buyerName: 'Night Buyer',
        buyerPhone: '',
        agentCode: 'AG-1',
        agentName: 'Seller A',
        drawCode: 'DEAR-8-PM',
        drawName: 'Dear 8 PM',
        ticketSeries: '12',
        ticketNumber: '12 54321',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(2026, 10, 29, 10, 0),
        drawDate: DateTime(2026, 10, 29, 20, 0),
      );

      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: [ticket],
      );

      // Must reject due to shift mismatch
      expect(claims, isEmpty);
    });

    test('Rule 5: Multi-Series Payout Scaling', () {
      final res = createKnownResult();
      // Ticket in Series 50 (50 multiplier) matching 2nd prize
      final ticket = TicketSaleModel(
        id: 'tkt_series_scaling',
        receiptNumber: 'REC-50-11111',
        buyerName: 'Wholesale Buyer',
        buyerPhone: '',
        agentCode: 'AG-1',
        agentName: 'Seller A',
        drawCode: 'DEAR-1-PM',
        drawName: 'Dear 1 PM',
        ticketSeries: '50',
        ticketNumber: '50 11111',
        quantity: 1,
        pricePerTicket: 6.0,
        totalAmount: 6.0,
        commissionAmount: 0.3,
        status: TicketStatus.sold,
        paymentMode: PaymentMode.cash,
        saleDate: DateTime(2026, 10, 29, 10, 0),
        drawDate: DateTime(2026, 10, 29, 13, 0),
      );

      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: [ticket],
      );

      expect(claims.length, equals(1));
      expect(claims.first.prizeTier, equals('🥈 2nd Prize'));
      expect(claims.first.seriesCount, equals(50));
      // (baseAmount 5000 + superBonus 2500 + specialIncentive 100) * 50 = 7600 * 50 = 380000
      expect(claims.first.prizeAmount, equals(380000.0));
    });
  });
}
