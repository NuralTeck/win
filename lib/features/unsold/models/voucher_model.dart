class VoucherModel {
  final String id;
  final String voucherNo;
  final String date; // YYYY-MM-DD
  final String drawShift; // e.g. 'Dear 1 PM'
  final String partyName;
  final String series;
  final String fromTicket;
  final String toTicket;
  final int totalQty;
  final double pricePerTicket;
  final double totalAmount;
  final DateTime createdAt;

  const VoucherModel({
    required this.id,
    required this.voucherNo,
    required this.date,
    required this.drawShift,
    required this.partyName,
    required this.series,
    required this.fromTicket,
    required this.toTicket,
    required this.totalQty,
    required this.pricePerTicket,
    required this.totalAmount,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voucher_no': voucherNo,
      'date': date,
      'draw_shift': drawShift,
      'party_name': partyName,
      'series': series,
      'from_ticket': fromTicket,
      'to_ticket': toTicket,
      'total_qty': totalQty,
      'price_per_ticket': pricePerTicket,
      'total_amount': totalAmount,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory VoucherModel.fromMap(Map<String, dynamic> map) {
    return VoucherModel(
      id: map['id']?.toString() ?? '',
      voucherNo: map['voucher_no']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      drawShift: map['draw_shift']?.toString() ?? '',
      partyName: map['party_name']?.toString() ?? '',
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
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
