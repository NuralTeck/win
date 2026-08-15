// Universal Ticket Series & Price Model
// Simple & Clean Model focusing strictly on Series Name & Price

class UniversalSeriesPriceModel {
  final String id;
  final String seriesName;   // e.g. '12', '24', 'A', etc.
  final double ticketPrice;  // Price in ₹
  final bool isActive;
  final DateTime createdAt;

  const UniversalSeriesPriceModel({
    required this.id,
    required this.seriesName,
    required this.ticketPrice,
    this.isActive = true,
    required this.createdAt,
  });

  // Getter compatibility for any legacy callers
  String get schemeType => 'Universal';
  double get mrp => ticketPrice;
  double get commissionRate => 0.0;

  UniversalSeriesPriceModel copyWith({
    String? id,
    String? seriesName,
    double? ticketPrice,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return UniversalSeriesPriceModel(
      id: id ?? this.id,
      seriesName: seriesName ?? this.seriesName,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
