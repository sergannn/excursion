import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';

class NewAssignment {
  const NewAssignment({
    required this.excursionId,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.roleInExcursion,
    required this.assignedAt,
  });

  final int excursionId;
  final String title;
  final String description;
  final String dateTime;
  final String roleInExcursion;
  final String assignedAt;

  factory NewAssignment.fromJson(Map<String, dynamic> json) {
    return NewAssignment(
      excursionId: json['excursion_id'] as int,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      dateTime: json['date_time'] as String,
      roleInExcursion: json['role_in_excursion'] as String,
      assignedAt: json['assigned_at'] as String,
    );
  }
}

class CheckAssignmentsResponse {
  const CheckAssignmentsResponse({
    required this.hasNew,
    required this.count,
    required this.assignments,
  });

  final bool hasNew;
  final int count;
  final List<NewAssignment> assignments;

  factory CheckAssignmentsResponse.fromJson(Map<String, dynamic> json) {
    final assignmentsList = json['assignments'] as List<dynamic>? ?? [];
    return CheckAssignmentsResponse(
      hasNew: json['has_new'] as bool? ?? false,
      count: json['count'] as int? ?? 0,
      assignments: assignmentsList
          .map((item) => NewAssignment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AssignmentsRepository {
  AssignmentsRepository(this._client);

  final ApiClient _client;

  Future<void> assignStaff({
    required int excursionId,
    required List<Map<String, dynamic>> assignments,
    String? excursionDate,
    String? time,
    int? slotMaxSeats,
  }) async {
    await _client.postJson(
      '/api/excursions/$excursionId/assign',
      authenticated: true,
      body: {
        'assignments': assignments,
        if (excursionDate != null) 'excursion_date': excursionDate,
        if (time != null) 'time': time,
        if (slotMaxSeats != null) 'slot_max_seats': slotMaxSeats,
      },
    );
  }

  Future<void> unassignStaff({
    required int excursionId,
    required int userId,
  }) async {
    await _client.deleteJson(
      '/api/excursions/$excursionId/assign/$userId',
      authenticated: true,
    );
  }

  Future<CheckAssignmentsResponse> checkNewAssignments({
    String? lastChecked,
  }) async {
    final queryParams = <String, dynamic>{};
    if (lastChecked != null) {
      queryParams['last_checked'] = lastChecked;
    }

    final response = await _client.getJson(
      '/api/excursions/check-new-assignments',
      authenticated: true,
      query: queryParams.isEmpty ? null : queryParams,
    );

    return CheckAssignmentsResponse.fromJson(response);
  }
}
