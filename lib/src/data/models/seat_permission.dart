class SeatPermission {
  const SeatPermission({
    required this.id,
    required this.excursionId,
    required this.userId,
    required this.excursionDate,
    required this.seatNumber,
    this.excursion,
    this.user,
    this.createdAt,
  });

  final int id;
  final int excursionId;
  final int userId;
  final DateTime excursionDate;
  final int seatNumber; // 1 or 2
  final SeatPermissionExcursion? excursion;
  final SeatPermissionUser? user;
  final DateTime? createdAt;

  factory SeatPermission.fromJson(Map<String, dynamic> json) {
    return SeatPermission(
      id: (json['id'] as num?)?.toInt() ?? 0,
      excursionId: (json['excursion_id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      excursionDate: DateTime.parse(json['excursion_date'] as String),
      seatNumber: (json['seat_number'] as num?)?.toInt() ?? 0,
      excursion: json['excursion'] != null
          ? SeatPermissionExcursion.fromJson(json['excursion'] as Map<String, dynamic>)
          : null,
      user: json['user'] != null
          ? SeatPermissionUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}

class SeatPermissionExcursion {
  const SeatPermissionExcursion({
    required this.id,
    required this.title,
  });

  final int id;
  final String title;

  factory SeatPermissionExcursion.fromJson(Map<String, dynamic> json) {
    return SeatPermissionExcursion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }
}

class SeatPermissionUser {
  const SeatPermissionUser({
    required this.id,
    required this.name,
    required this.email,
  });

  final int id;
  final String name;
  final String email;

  factory SeatPermissionUser.fromJson(Map<String, dynamic> json) {
    return SeatPermissionUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
    );
  }
}


