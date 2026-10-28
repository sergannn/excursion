import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';
import '../models/schedule_template.dart';

class ScheduleRepository {
  ScheduleRepository(this._client);

  final ApiClient _client;

  Future<List<ScheduleTemplate>> fetchSchedule() async {
    final response =
        await _client.getJson('/api/schedule', authenticated: false);
    final data = response['data'] as List<dynamic>?;
    if (data == null) {
      return const [];
    }
    return data
        .map((json) => ScheduleTemplate.fromJson(json as Map<String, dynamic>))
        .toList();
  }
}
