class UnsoldModel {
  final String id;
  final String returnNo;
  final String date; // YYYY-MM-DD
  final String drawShift; // e.g. 'Dear 1 PM'
  final String partyName;
  final String series;
  final String fromTicket;
  final String toTicket;
  final int totalQty;
  final double pricePerTicket;
  final double totalAmount;
  final bool isLocked;
  final DateTime createdAt;
  final String? dealerName; // 🏢 Main Parent Dealer if unsold is returned by a sub-seller

  const UnsoldModel({
    required this.id,
    required this.returnNo,
    required this.date,
    required this.drawShift,
    required this.partyName,
    required this.series,
    required this.fromTicket,
    required this.toTicket,
    required this.totalQty,
    required this.pricePerTicket,
    required this.totalAmount,
    this.isLocked = false,
    required this.createdAt,
    this.dealerName,
  });

  String get effectiveDealer => (dealerName != null && dealerName!.isNotEmpty) ? dealerName! : partyName;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'return_no': returnNo,
      'date': date,
      'draw_shift': drawShift,
      'party_name': partyName,
      'dealer_name': dealerName ?? partyName,
      'series': series,
      'from_ticket': fromTicket,
      'to_ticket': toTicket,
      'total_qty': totalQty,
      'price_per_ticket': pricePerTicket,
      'total_amount': totalAmount,
      'is_locked': isLocked ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory UnsoldModel.fromMap(Map<String, dynamic> map) {
    final party = map['party_name']?.toString() ?? '';
    final dealer = map['dealer_name']?.toString();
    return UnsoldModel(
      id: map['id']?.toString() ?? '',
      returnNo: map['return_no']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      drawShift: map['draw_shift']?.toString() ?? '',
      partyName: party,
      dealerName: (dealer != null && dealer.isNotEmpty) ? dealer : party,
      series: map['series']?.toString() ?? '',
      fromTicket: map['from_ticket']?.toString() ?? '',
      toTicket: map['to_ticket']?.toString() ?? '',
      totalQty: (map['total_qty'] is int)
          ? map['total_qty']
          : int.tryParse(map['total_qty']?.toString() ?? '0') ?? 0,
      pricePerTicket: (map['price_per_ticket'] is num)
          ? (map['price_per_ticket'] as num).toDouble()
          : double.tryParse(map['price_per_ticket']?.toString() ?? '0.0') ?? 0.0,
      totalAmount: (map['total_amount'] is num)
          ? (map['total_amount'] as num).toDouble()
          : double.tryParse(map['total_amount']?.toString() ?? '0.0') ?? 0.0,
      isLocked: map['is_locked'] == 1 || map['is_locked'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
