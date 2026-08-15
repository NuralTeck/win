// Nagaland Lottery – Draw / Scheme model
// Replaces generic OperationModel with lottery-specific fields

enum DrawStatus {
  open,       // Currently accepting entries
  closed,     // Entry closed, draw pending
  completed,  // Winner declared
  suspended,  // Paused by authority
  cancelled,  // Cancelled draw
}

enum DrawPriority {
  bumperSpecial, // State-level mega bumper
  daily,         // Morning / Evening draw
  weekly,        // Weekly lucky draw
  festival,      // Festival / Special occasion
}

class DrawModel {
  final String id;
  final String drawCode;        // e.g. NL-DR-2401
  final String drawName;        // e.g. "Dear Morning Monday"
  final String schemeType;      // e.g. "Daily", "Bumper", "Festival"
  final String conductedBy;     // e.g. "Nagaland State Lotteries"
  final DrawStatus status;
  final DrawPriority priority;
  final double ticketPrice;     // Price per ticket (₹)
  final int totalTickets;
  final int ticketsSold;
  final double prizePool;       // Total prize pool (₹)
  final DateTime drawDate;
  final DateTime updatedAt;
  final String district;        // District handling the draw

  const DrawModel({
    required this.id,
    required this.drawCode,
    required this.drawName,
    required this.schemeType,
    required this.conductedBy,
    required this.status,
    required this.priority,
    required this.ticketPrice,
    required this.totalTickets,
    required this.ticketsSold,
    required this.prizePool,
    required this.drawDate,
    required this.updatedAt,
    required this.district,
  });

  double get salesProgress =>
      totalTickets == 0 ? 0 : (ticketsSold / totalTickets).clamp(0.0, 1.0);

  int get ticketsRemaining => totalTickets - ticketsSold;

  DrawModel copyWith({
    String? id,
    String? drawCode,
    String? drawName,
    String? schemeType,
    String? conductedBy,
    DrawStatus? status,
    DrawPriority? priority,
    double? ticketPrice,
    int? totalTickets,
    int? ticketsSold,
    double? prizePool,
    DateTime? drawDate,
    DateTime? updatedAt,
    String? district,
  }) {
    return DrawModel(
      id: id ?? this.id,
      drawCode: drawCode ?? this.drawCode,
      drawName: drawName ?? this.drawName,
      schemeType: schemeType ?? this.schemeType,
      conductedBy: conductedBy ?? this.conductedBy,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      ticketPrice: ticketPrice ?? this.ticketPrice,
      totalTickets: totalTickets ?? this.totalTickets,
      ticketsSold: ticketsSold ?? this.ticketsSold,
      prizePool: prizePool ?? this.prizePool,
      drawDate: drawDate ?? this.drawDate,
      updatedAt: updatedAt ?? this.updatedAt,
      district: district ?? this.district,
    );
  }
}
