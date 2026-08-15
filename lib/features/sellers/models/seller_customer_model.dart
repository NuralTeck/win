class SellerCustomerModel {
  final String id;
  final String name;
  final String accessKey;
  final String password;
  final String phone;
  final bool isActive;
  final DateTime createdAt;

  SellerCustomerModel({
    required this.id,
    required this.name,
    required this.accessKey,
    required this.password,
    required this.phone,
    this.isActive = true,
    required this.createdAt,
  });

  SellerCustomerModel copyWith({
    String? id,
    String? name,
    String? accessKey,
    String? password,
    String? phone,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return SellerCustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      accessKey: accessKey ?? this.accessKey,
      password: password ?? this.password,
      phone: phone ?? this.phone,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
