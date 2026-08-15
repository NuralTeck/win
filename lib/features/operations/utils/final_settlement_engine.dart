import '../../shared/models/ticket_sale_model.dart';
import '../models/winning_claim_model.dart';
import '../models/prize_config_model.dart';
import '../models/lottery_sambad_result_model.dart';
import 'winner_verification_engine.dart';

/// Final Settlement Summary Data Structure
class FinalSettlementSummaryModel {
  final String sellerName;
  final String dateStr;
  final String shiftName;
  final int totalTicketsSold;
  final double grossTicketBill;
  final double sellerCommission;
  final double totalWinningPayout;
  final double netCollectibleCash;
  final List<WinningClaimModel> winningClaims;

  FinalSettlementSummaryModel({
    required this.sellerName,
    required this.dateStr,
    required this.shiftName,
    required this.totalTicketsSold,
    required this.grossTicketBill,
    required this.sellerCommission,
    required this.totalWinningPayout,
    required this.netCollectibleCash,
    required this.winningClaims,
  });

  bool get isPositiveBalance => netCollectibleCash >= 0;
}

/// Final Settlement Engine
/// Calculates complete financial settlement for Sellers & Dealers
class FinalSettlementEngine {
  static FinalSettlementSummaryModel calculateSettlement({
    required String sellerName,
    required String dateStr,
    required String shiftName,
    required List<TicketSaleModel> sales,
    required List<LotterySambadResultModel> results,
    Map<int, PrizeTierConfigModel>? prizeConfig,
    double commissionRate = 0.05,
  }) {
    final List<WinningClaimModel> allClaims = [];

    // 1. Calculate Winners across matching results
    for (final res in results) {
      final claims = WinnerVerificationEngine.verifyWinners(
        result: res,
        soldTickets: sales,
        prizeConfig: prizeConfig,
      );
      allClaims.addAll(claims);
    }

    // 2. Financial Totals
    final int totalTickets = sales.fold(0, (sum, s) => sum + s.quantity);
    final double grossSales = sales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final double commission = sales.fold(
      0.0,
      (sum, s) => sum + (s.totalAmount * commissionRate),
    );
    final double totalInam = allClaims.fold(
      0.0,
      (sum, c) => sum + c.prizeAmount,
    );
    final double netCash = grossSales - commission - totalInam;

    return FinalSettlementSummaryModel(
      sellerName: sellerName,
      dateStr: dateStr,
      shiftName: shiftName,
      totalTicketsSold: totalTickets,
      grossTicketBill: grossSales,
      sellerCommission: commission,
      totalWinningPayout: totalInam,
      netCollectibleCash: netCash,
      winningClaims: allClaims,
    );
  }
}
