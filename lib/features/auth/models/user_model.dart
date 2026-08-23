class UserModel {
  final String id;
  final String username;
  final String fullName;
  final String role;
  final String phone;
  final bool isActive;
  final DateTime createdAt;

  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.phone = '',
    this.isActive = true,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      fullName: map['fullName']?.toString() ?? '',
      role: map['role']?.toString() ?? 'Administrator',
      phone: map['phone']?.toString() ?? '',
      isActive: (map['isActive'] is int ? map['isActive'] == 1 : map['isActive'] == true),
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'fullName': fullName,
      'role': role,
      'phone': phone,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
