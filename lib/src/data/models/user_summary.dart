class UserSummary {
  const UserSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.roleName,
    required this.roleId,
    required this.balance,
    this.password,
    this.color,
    this.busId,
    this.busNumber,
  });

  final int id;
  final String name;
  final String email;
  final String roleName;
  final int roleId;
  final double balance;
  final String? password;
  final String? color; // HEX цвет, например #FF5733
  final int? busId;
  final String? busNumber;

  factory UserSummary.fromJson(Map<String, dynamic> json) {
    String roleName = 'Unknown';
    if (json['role'] is String && (json['role'] as String).isNotEmpty) {
      roleName = json['role'] as String;
    } else if (json['moonshine_user_role'] is Map<String, dynamic>) {
      final role = json['moonshine_user_role'] as Map<String, dynamic>;
      final value = role['name'];
      if (value is String && value.isNotEmpty) {
        roleName = value;
      }
    }

    final roleId = (json['role_id'] as num?)?.toInt() ??
        (json['moonshine_user_role_id'] as num?)?.toInt() ??
        0;
    return UserSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      roleName: roleName,
      roleId: roleId,
      balance: double.tryParse(json['balance']?.toString() ?? '0') ?? 0,
      password: json['password'] as String?,
      color: json['color'] as String?,
      busId: (json['bus_id'] as num?)?.toInt(),
      busNumber: json['bus'] is Map<String, dynamic>
          ? (json['bus'] as Map<String, dynamic>)['number']?.toString()
          : null,
    );
  }
}
