class Stop {
  const Stop({
    required this.id,
    required this.name,
    required this.order,
  });

  final int id;
  final String name;
  final int order;

  factory Stop.fromJson(Map<String, dynamic> json) {
    return Stop(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      order: json['order'] as int? ?? 0,
    );
  }
}
