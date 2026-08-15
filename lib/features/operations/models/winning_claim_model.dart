// Winning Ticket Claim Model for Result PDF Auto-Match Engine

class WinningClaimModel {
  final String id;
  final String drawId;
  final String drawName;
  final String prizeTier;      // "1st Prize", "2nd Prize", "3rd Prize", "4th Prize", "5th Prize"
  final String winningNumber;  // e.g. "83L 28311", "28311", "04812"
  final double prizeAmount;    // Total Payout = (baseAmount * seriesCount) + superBonus + specialIncentive
  final int seriesCount;       // Number of series booked for this winning number
  final double baseAmount;     // Base prize per series
  final double superBonus;     // Fixed Super Bonus
  final double specialIncentive;// Fixed Special Incentive
  final String buyerName;      // Winning customer
  final String sellerName;     // Selling agent
  final String ticketSeries;   // e.g. "83L" or "12"
  final String ticketNumber;   // e.g. "28311"
  final bool isClaimed;
  final DateTime verifiedAt;

  const WinningClaimModel({
    required this.id,
    required this.drawId,
    required this.drawName,
    required this.prizeTier,
    required this.winningNumber,
    required this.prizeAmount,
    this.seriesCount = 1,
    this.baseAmount = 0.0,
    this.superBonus = 0.0,
    this.specialIncentive = 0.0,
    required this.buyerName,
    required this.sellerName,
    required this.ticketSeries,
    required this.ticketNumber,
    this.isClaimed = false,
    required this.verifiedAt,
  });

  WinningClaimModel copyWith({
    String? id,
    String? drawId,
    String? drawName,
    String? prizeTier,
    String? winningNumber,
    double? prizeAmount,
    int? seriesCount,
    double? baseAmount,
    double? superBonus,
    double? specialIncentive,
    String? buyerName,
    String? sellerName,
    String? ticketSeries,
    String? ticketNumber,
    bool? isClaimed,
    DateTime? verifiedAt,
  }) {
    return WinningClaimModel(
      id: id ?? this.id,
      drawId: drawId ?? this.drawId,
      drawName: drawName ?? this.drawName,
      prizeTier: prizeTier ?? this.prizeTier,
      winningNumber: winningNumber ?? this.winningNumber,
      prizeAmount: prizeAmount ?? this.prizeAmount,
      seriesCount: seriesCount ?? this.seriesCount,
      baseAmount: baseAmount ?? this.baseAmount,
      superBonus: superBonus ?? this.superBonus,
      specialIncentive: specialIncentive ?? this.specialIncentive,
      buyerName: buyerName ?? this.buyerName,
      sellerName: sellerName ?? this.sellerName,
      ticketSeries: ticketSeries ?? this.ticketSeries,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      isClaimed: isClaimed ?? this.isClaimed,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}
