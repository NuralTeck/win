// Winning Ticket Claim Model for Result PDF Auto-Match Engine

class WinningClaimModel {
  final String id;
  final String drawId;
  final String drawName;
  final String? drawDate;      // e.g. "17-10-2026" or "17/10/2026"
  final String? drawTime;      // e.g. "01:00 PM" or "1 PM"
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
    this.drawDate,
    this.drawTime,
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

  String get displayDate {
    if (drawDate != null && drawDate!.trim().isNotEmpty) return drawDate!.trim();
    final m = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(drawId);
    if (m != null) return m.group(0)!;
    final m2 = RegExp(r'\d{2}[-./]\d{2}[-./]\d{4}').firstMatch(drawId);
    if (m2 != null) return m2.group(0)!;
    return '${verifiedAt.day.toString().padLeft(2, '0')}-${verifiedAt.month.toString().padLeft(2, '0')}-${verifiedAt.year}';
  }

  String get displayTime {
    if (drawTime != null && drawTime!.trim().isNotEmpty) return drawTime!.trim();
    if (drawName.contains('1:00 PM') || drawName.contains('1 PM') || drawName.contains('1PM') || drawId.contains('1PM')) return '1:00 PM';
    if (drawName.contains('6:00 PM') || drawName.contains('6 PM') || drawName.contains('6PM') || drawId.contains('6PM')) return '6:00 PM';
    if (drawName.contains('8:00 PM') || drawName.contains('8 PM') || drawName.contains('8PM') || drawId.contains('8PM')) return '8:00 PM';
    return drawName.isNotEmpty ? drawName : 'Draw Time';
  }

  WinningClaimModel copyWith({
    String? id,
    String? drawId,
    String? drawName,
    String? drawDate,
    String? drawTime,
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
      drawDate: drawDate ?? this.drawDate,
      drawTime: drawTime ?? this.drawTime,
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
