// Nagaland Lottery – Ticket Agent model
// Replaces generic SellerModel with lottery-agent-specific fields

enum AgentLicense {
  master,     // Master distributor
  district,   // District agent
  retail,     // Retail outlet
  stockist,   // Stockist / Sub-agent
}

enum AgentStatus {
  active,
  underReview,
  suspended,
}

class AgentModel {
  final String id;
  final String agentCode;       // e.g. NLA-0091
  final String agentName;       // e.g. "Sunrise Lottery Center"
  final String ownerName;       // e.g. "Ravi Kumar"
  final AgentLicense license;
  final AgentStatus status;
  final double monthlySales;    // ₹ total ticket sales
  final int ticketsSold;        // total tickets sold this month
  final double commissionRate;  // e.g. 5.0 (percent)
  final double commissionEarned; // ₹ commission earned
  final double rating;          // 1.0 – 5.0
  final String district;        // Kohima, Dimapur, Mokokchung…
  final List<double> salesSparkline;

  const AgentModel({
    required this.id,
    required this.agentCode,
    required this.agentName,
    required this.ownerName,
    required this.license,
    required this.status,
    required this.monthlySales,
    required this.ticketsSold,
    required this.commissionRate,
    required this.commissionEarned,
    required this.rating,
    required this.district,
    required this.salesSparkline,
  });
}
