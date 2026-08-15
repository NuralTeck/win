class CollectorModel {
  final String id;
  final String accessKey;
  final String name;
  final String phone;
  final String password;
  final bool isActive;
  final DateTime createdAt;

  CollectorModel({
    required this.id,
    required this.accessKey,
    required this.name,
    required this.phone,
    required this.password,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'access_key': accessKey,
      'name': name,
      'phone': phone,
      'password': password,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory CollectorModel.fromMap(Map<String, dynamic> map) {
    return CollectorModel(
      id: map['id']?.toString() ?? '',
      accessKey: map['access_key']?.toString() ?? map['accessKey']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      isActive: (map['is_active'] == 1 || map['is_active'] == true || map['isActive'] == true),
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class CollectorPaymentModel {
  final String id;
  final String collectorId;
  final String collectorName;
  final String sellerId;
  final String sellerName;
  final double amount;
  final String paymentMode; // 'Cash' or 'Online'
  final String refNumber;
  final String remark;
  final DateTime collectedAt;

  CollectorPaymentModel({
    required this.id,
    required this.collectorId,
    required this.collectorName,
    required this.sellerId,
    required this.sellerName,
    required this.amount,
    required this.paymentMode,
    required this.refNumber,
    required this.remark,
    required this.collectedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'collector_id': collectorId,
      'collector_name': collectorName,
      'seller_id': sellerId,
      'seller_name': sellerName,
      'amount': amount,
      'payment_mode': paymentMode,
      'ref_number': refNumber,
      'remark': remark,
      'collected_at': collectedAt.toIso8601String(),
    };
  }

  factory CollectorPaymentModel.fromMap(Map<String, dynamic> map) {
    return CollectorPaymentModel(
      id: map['id']?.toString() ?? '',
      collectorId: map['collector_id']?.toString() ?? map['collectorId']?.toString() ?? '',
      collectorName: map['collector_name']?.toString() ?? map['collectorName']?.toString() ?? '',
      sellerId: map['seller_id']?.toString() ?? map['sellerId']?.toString() ?? '',
      sellerName: map['seller_name']?.toString() ?? map['sellerName']?.toString() ?? '',
      amount: (map['amount'] is num) ? (map['amount'] as num).toDouble() : double.tryParse(map['amount']?.toString() ?? '0') ?? 0.0,
      paymentMode: map['payment_mode']?.toString() ?? map['paymentMode']?.toString() ?? 'Cash',
      refNumber: map['ref_number']?.toString() ?? map['refNumber']?.toString() ?? '',
      remark: map['remark']?.toString() ?? '',
      collectedAt: DateTime.tryParse(map['collected_at']?.toString() ?? map['collectedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
