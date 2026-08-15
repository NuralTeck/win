// Nagaland Lottery – Ticket Sale / Booking model
// Replaces generic BookingModel with full ticket-sale details

enum TicketStatus {
  sold,        // Sold and confirmed
  pending,     // Payment pending
  cancelled,   // Cancelled
  won,         // Winning ticket
  claimed,     // Prize claimed
  expired,     // Unclaimed / expired
}

enum PaymentMode {
  cash,
  upi,
  netBanking,
  card,
  challan, // Government challan
}

class TicketSaleModel {
  final String id;
  final String receiptNumber;    // e.g. TKT-2026-91240
  final String buyerName;        // Customer / Buyer name
  final String buyerPhone;       // Buyer mobile number
  final String agentCode;        // Agent who sold
  final String agentName;        // Agent name
  final String drawCode;         // Draw this ticket is for
  final String drawName;         // Draw name
  final String ticketSeries;     // e.g. "A", "B", "C"
  final String ticketNumber;     // e.g. "A 456789"
  final int quantity;            // Number of tickets
  final double pricePerTicket;   // ₹ per ticket
  final double totalAmount;      // quantity × pricePerTicket
  final double commissionAmount; // Agent commission (₹)
  final TicketStatus status;
  final PaymentMode paymentMode;
  final DateTime saleDate;
  final DateTime drawDate;

  const TicketSaleModel({
    required this.id,
    required this.receiptNumber,
    required this.buyerName,
    required this.buyerPhone,
    required this.agentCode,
    required this.agentName,
    required this.drawCode,
    required this.drawName,
    required this.ticketSeries,
    required this.ticketNumber,
    required this.quantity,
    required this.pricePerTicket,
    required this.totalAmount,
    required this.commissionAmount,
    required this.status,
    required this.paymentMode,
    required this.saleDate,
    required this.drawDate,
  });

  TicketSaleModel copyWith({
    String? id,
    String? receiptNumber,
    String? buyerName,
    String? buyerPhone,
    String? agentCode,
    String? agentName,
    String? drawCode,
    String? drawName,
    String? ticketSeries,
    String? ticketNumber,
    int? quantity,
    double? pricePerTicket,
    double? totalAmount,
    double? commissionAmount,
    TicketStatus? status,
    PaymentMode? paymentMode,
    DateTime? saleDate,
    DateTime? drawDate,
  }) {
    return TicketSaleModel(
      id: id ?? this.id,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      buyerName: buyerName ?? this.buyerName,
      buyerPhone: buyerPhone ?? this.buyerPhone,
      agentCode: agentCode ?? this.agentCode,
      agentName: agentName ?? this.agentName,
      drawCode: drawCode ?? this.drawCode,
      drawName: drawName ?? this.drawName,
      ticketSeries: ticketSeries ?? this.ticketSeries,
      ticketNumber: ticketNumber ?? this.ticketNumber,
      quantity: quantity ?? this.quantity,
      pricePerTicket: pricePerTicket ?? this.pricePerTicket,
      totalAmount: totalAmount ?? this.totalAmount,
      commissionAmount: commissionAmount ?? this.commissionAmount,
      status: status ?? this.status,
      paymentMode: paymentMode ?? this.paymentMode,
      saleDate: saleDate ?? this.saleDate,
      drawDate: drawDate ?? this.drawDate,
    );
  }
}
