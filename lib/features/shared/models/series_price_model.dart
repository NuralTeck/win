// Universal Ticket Series & Price Model
// Simple & Clean Model focusing strictly on Series Name & Price

class UniversalSeriesPriceModel {
  final String id;
  final String seriesName;   // e.g. '12', '24', 'A', etc.
  final double ticketPrice;  // Price in ₹
  final bool isActive;
  final DateTime createdAt;
  final int? colorValue;     // 32-bit ARGB color value (e.g. 0xFF2DD4BF)

  const UniversalSeriesPriceModel({
    required this.id,
    required this.seriesName,
    required this.ticketPrice,
    this.isActive = true,
    required this.createdAt,
    this.colorValue,
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
    int? colorValue,
  }) {
    return UniversalSeriesPriceModel(
      id: id ?? this.id,
      seriesName: seriesName ?? this.seriesName,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      colorValue: colorValue ?? this.colorValue,
    );
  }
}
