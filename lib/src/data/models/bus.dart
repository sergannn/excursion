import 'user_summary.dart';

class Bus {
  const Bus({
    required this.id,
    required this.number,
    this.model,
    required this.capacity,
    this.licensePlate,
    required this.isActive,
    this.drivers,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String number;
  final String? model;
  final int capacity;
  final String? licensePlate;
  final bool isActive;
  final List<UserSummary>? drivers;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Bus.fromJson(Map<String, dynamic> json) {
    return Bus(
      id: (json['id'] as num?)?.toInt() ?? 0,
      number: json['number'] as String? ?? '',
      model: json['model'] as String?,
      capacity: (json['capacity'] as num?)?.toInt() ?? 0,
      licensePlate: json['license_plate'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      drivers: json['drivers'] != null
          ? (json['drivers'] as List<dynamic>)
              .map((e) => UserSummary.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'number': number,
      'model': model,
      'capacity': capacity,
      'license_plate': licensePlate,
      'is_active': isActive,
      'drivers': drivers?.map((e) => {
        'id': e.id,
        'name': e.name,
        'email': e.email,
      }).toList(),
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
