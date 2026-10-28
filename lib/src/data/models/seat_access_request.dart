class SeatAccessRequest {
  const SeatAccessRequest({
    required this.id,
    required this.excursionId,
    required this.userId,
    required this.excursionDate,
    required this.seatNumber,
    required this.status,
    this.excursion,
    this.user,
    this.reviewer,
    this.reason,
    this.reviewedAt,
    this.createdAt,
  });

  final int id;
  final int excursionId;
  final int userId;
  final DateTime excursionDate;
  final int seatNumber; // 1 or 2
  final String status; // 'pending', 'approved', 'rejected'
  final SeatAccessRequestExcursion? excursion;
  final SeatAccessRequestUser? user;
  final SeatAccessRequestUser? reviewer;
  final String? reason;
  final DateTime? reviewedAt;
  final DateTime? createdAt;

  factory SeatAccessRequest.fromJson(Map<String, dynamic> json) {
    return SeatAccessRequest(
      id: (json['id'] as num?)?.toInt() ?? 0,
      excursionId: (json['excursion_id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      excursionDate: DateTime.parse(json['excursion_date'] as String),
      seatNumber: (json['seat_number'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      excursion: json['excursion'] != null
          ? SeatAccessRequestExcursion.fromJson(json['excursion'] as Map<String, dynamic>)
          : null,
      user: json['user'] != null
          ? SeatAccessRequestUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      reviewer: json['reviewer'] != null
          ? SeatAccessRequestUser.fromJson(json['reviewer'] as Map<String, dynamic>)
          : null,
      reason: json['reason'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class SeatAccessRequestExcursion {
  const SeatAccessRequestExcursion({
    required this.id,
    required this.title,
  });

  final int id;
  final String title;

  factory SeatAccessRequestExcursion.fromJson(Map<String, dynamic> json) {
    return SeatAccessRequestExcursion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
    );
  }
}

class SeatAccessRequestUser {
  const SeatAccessRequestUser({
    required this.id,
    required this.name,
    this.email,
  });

  final int id;
  final String name;
  final String? email;

  factory SeatAccessRequestUser.fromJson(Map<String, dynamic> json) {
    return SeatAccessRequestUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
    );
  }
}


