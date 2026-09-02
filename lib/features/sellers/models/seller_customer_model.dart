class SellerCustomerModel {
  final String id;
  final String name;
  final String accessKey;
  final String password;
  final String phone;
  final bool isActive;
  final DateTime createdAt;
  final String? parentDealer; // 🏢 Name of Parent Dealer if this is a sub-seller
  final bool isDealer; // 👑 True if this party is a main dealer

  SellerCustomerModel({
    required this.id,
    required this.name,
    required this.accessKey,
    required this.password,
    required this.phone,
    this.isActive = true,
    required this.createdAt,
    this.parentDealer,
    this.isDealer = false,
  });

  SellerCustomerModel copyWith({
    String? id,
    String? name,
    String? accessKey,
    String? password,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
    String? parentDealer,
    bool? isDealer,
  }) {
    return SellerCustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      accessKey: accessKey ?? this.accessKey,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      parentDealer: parentDealer ?? this.parentDealer,
      isDealer: isDealer ?? this.isDealer,
    );
  }
}
