enum SellerTier {
  enterprise,
  gold,
  silver,
  standard,
}

enum SellerStatus {
  active,
  underReview,
  suspended,
}

class SellerModel {
  final String id;
  final String code;
  final String name;
  final String category;
  final SellerTier tier;
  final SellerStatus status;
  final double monthlyRevenue;
  final int totalBookings;
  final double fulfillmentRate; // e.g. 99.4%
  final double rating; // e.g. 4.9
  final String region;
  final List<double> revenueSparkline;

  const SellerModel({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.tier,
    required this.status,
    required this.monthlyRevenue,
    required this.totalBookings,
    required this.fulfillmentRate,
    required this.rating,
    required this.region,
    required this.revenueSparkline,
  });
}
