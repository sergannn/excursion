class ScheduleDay {
  const ScheduleDay({
    required this.dayNumber,
    required this.dayName,
    required this.time,
  });

  final int dayNumber;
  final String dayName;
  final String time;

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    return ScheduleDay(
      dayNumber: (json['day_number'] as num?)?.toInt() ?? 0,
      dayName: json['day_name'] as String,
      time: json['time'] as String,
    );
  }
}

class ScheduleTemplate {
  const ScheduleTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.schedule,
  });

  final int id;
  final String title;
  final String description;
  final List<ScheduleDay> schedule;

  factory ScheduleTemplate.fromJson(Map<String, dynamic> json) {
    final scheduleJson = json['schedule'] as List<dynamic>? ?? [];
    return ScheduleTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String,
      description: json['description'] as String,
      schedule: scheduleJson
          .map((item) => ScheduleDay.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
