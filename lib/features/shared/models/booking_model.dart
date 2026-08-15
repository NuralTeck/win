enum BookingStatus {
  confirmed,
  processing,
  settled,
  refunded,
  flagged,
}

class BookingModel {
  final String id;
  final String referenceNumber;
  final String customerName;
  final String sellerName;
  final String serviceType;
  final double amount;
  final double commissionFee;
  final BookingStatus status;
  final DateTime bookingDate;
  final String paymentMethod;

  const BookingModel({
    required this.id,
    required this.referenceNumber,
    required this.customerName,
    required this.sellerName,
    required this.serviceType,
    required this.amount,
    required this.commissionFee,
    required this.status,
    required this.bookingDate,
    required this.paymentMethod,
  });
}
