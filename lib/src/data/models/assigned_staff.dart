class AssignedStaff {
  const AssignedStaff({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final int id;
  final String name;
  final String email;
  final String role; // driver | guide

  factory AssignedStaff.fromJson(Map<String, dynamic> json) {
    return AssignedStaff(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role_in_excursion'] as String? ?? '',
    );
  }
}
