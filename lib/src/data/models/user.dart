class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.roleId,
    required this.isSuperUser,
    this.color,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final int roleId;
  final bool isSuperUser;
  final String? color;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      roleId: (json['role_id'] as num?)?.toInt() ?? 0,
      isSuperUser: json['is_super_user'] as bool? ?? false,
      color: json['color'] as String?,
    );
  }
}
