import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/api_helpers.dart';
import '../models/bus.dart';

class BusesRepository {
  BusesRepository(this._client);

  final ApiClient _client;

  Future<List<Bus>> fetchBuses({bool? isActive, String? search}) async {
    try {
      final query = <String, dynamic>{};
      if (isActive != null) {
        query['is_active'] = isActive;
      }
      if (search != null && search.isNotEmpty) {
        query['search'] = search;
      }

      final response = await _client.getJson(
        '/api/buses',
        query: query,
        authenticated: true,
      );
      final items = response['buses'] as List<dynamic>? ?? const [];
      return items
          .map((item) => Bus.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  Future<Bus> fetchBus(int id) async {
    try {
      final response = await _client.getJson(
        '/api/buses/$id',
        authenticated: true,
      );
      return Bus.fromJson(response['bus'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    }
  }

  Future<Bus> createBus({
    required String number,
    String? model,
    required int capacity,
    String? licensePlate,
    bool isActive = true,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/buses',
        authenticated: true,
        body: {
          'number': number,
          'model': model,
          'capacity': capacity,
          'license_plate': licensePlate,
          'is_active': isActive,
        },
      );
      return Bus.fromJson(response['bus'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    }
  }

  Future<Bus> updateBus(
    int id, {
    String? number,
    String? model,
    int? capacity,
    String? licensePlate,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (number != null) body['number'] = number;
      if (model != null) body['model'] = model;
      if (capacity != null) body['capacity'] = capacity;
      if (licensePlate != null) body['license_plate'] = licensePlate;
      if (isActive != null) body['is_active'] = isActive;

      final response = await _client.putJson(
        '/api/buses/$id',
        authenticated: true,
        body: body,
      );
      return Bus.fromJson(response['bus'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    }
  }

  Future<void> deleteBus(int id) async {
    try {
      await _client.deleteJson(
        '/api/buses/$id',
        authenticated: true,
      );
    } on ApiException {
      rethrow;
    }
  }

  Future<void> assignToDriver(int busId, int driverId) async {
    try {
      await _client.postJson(
        '/api/buses/$busId/assign-driver',
        authenticated: true,
        body: {'driver_id': driverId},
      );
    } on ApiException {
      rethrow;
    }
  }

  Future<void> unassignFromDriver(int busId, int driverId) async {
    try {
      await _client.postJson(
        '/api/buses/$busId/unassign-driver',
        authenticated: true,
        body: {'driver_id': driverId},
      );
    } on ApiException {
      rethrow;
    }
  }

  Future<void> assignToExcursion({
    required int busId,
    required int excursionId,
    required int driverId,
    required String excursionDate,
    required String time,
  }) async {
    try {
      await _client.postJson(
        '/api/buses/$busId/assign-excursion',
        authenticated: true,
        body: {
          'excursion_id': excursionId,
          'driver_id': driverId,
          'excursion_date': excursionDate,
          'time': time,
        },
      );
    } on ApiException {
      rethrow;
    }
  }

  Future<void> unassignFromExcursion({
    required int busId,
    required int excursionId,
    required String excursionDate,
    required String time,
  }) async {
    try {
      await _client.postJson(
        '/api/buses/$busId/unassign-excursion',
        authenticated: true,
        body: {
          'excursion_id': excursionId,
          'excursion_date': excursionDate,
          'time': time,
        },
      );
    } on ApiException {
      rethrow;
    }
  }
}
