import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';
import '../models/stop.dart';

class StopsRepository {
  StopsRepository(this._client);

  final ApiClient _client;

  Future<List<Stop>> fetchStops() async {
    final response = await _client.getJson('/api/stops');
    final items = response['stops'] as List<dynamic>? ?? const [];
    return items
        .map((item) => Stop.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Stop>> fetchStopsForExcursion(int excursionId) async {
    final response =
        await _client.getJson(
      '/api/excursions/$excursionId/stops',
      authenticated: true,
    );
    final stopsList = response['stops'] as List<dynamic>? ?? [];
    return stopsList
        .map((item) => Stop.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
