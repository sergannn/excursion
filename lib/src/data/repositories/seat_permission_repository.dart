import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/api_helpers.dart';
import '../models/seat_permission.dart';
import '../models/seat_access_request.dart';

class SeatPermissionRepository {
  SeatPermissionRepository(this._client);

  final ApiClient _client;

  // Проверить разрешения для текущего пользователя
  Future<Map<String, bool>> checkPermissions({
    required int excursionId,
    required String excursionDate,
  }) async {
    try {
      final response = await _client.getJson(
        '/api/seat-permissions/check',
        query: {
          'excursion_id': excursionId,
          'excursion_date': excursionDate,
        },
        authenticated: true,
      );

      return {
        'has_permission_for_seat_1': response['has_permission_for_seat_1'] as bool? ?? false,
        'has_permission_for_seat_2': response['has_permission_for_seat_2'] as bool? ?? false,
      };
    } on ApiException {
      rethrow;
    }
  }

  // Получить список разрешений
  Future<List<SeatPermission>> fetchPermissions({
    int? excursionId,
    String? excursionDate,
    int? userId,
  }) async {
    try {
      final query = <String, dynamic>{};
      if (excursionId != null) query['excursion_id'] = excursionId;
      if (excursionDate != null) query['excursion_date'] = excursionDate;
      if (userId != null) query['user_id'] = userId;

      final response = await _client.getJson(
        '/api/seat-permissions',
        query: query,
        authenticated: true,
      );

      final items = response['permissions'] as List<dynamic>? ?? const [];
      return items
          .map((item) => SeatPermission.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  // Создать разрешение
  Future<SeatPermission> createPermission({
    required int excursionId,
    required int userId,
    required String excursionDate,
    required int seatNumber,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/seat-permissions',
        body: {
          'excursion_id': excursionId,
          'user_id': userId,
          'excursion_date': excursionDate,
          'seat_number': seatNumber,
        },
        authenticated: true,
      );

      // API возвращает permission в поле 'permission'
      final permissionData = response['permission'] as Map<String, dynamic>;
      // Нужно получить полные данные, поэтому делаем запрос заново
      final permissions = await fetchPermissions(
        excursionId: excursionId,
        excursionDate: excursionDate,
        userId: userId,
      );
      return permissions.firstWhere(
        (p) => p.seatNumber == seatNumber,
        orElse: () => SeatPermission.fromJson(permissionData),
      );
    } on ApiException {
      rethrow;
    }
  }

  // Удалить разрешение
  Future<void> deletePermission(int permissionId) async {
    try {
      await _client.deleteJson(
        '/api/seat-permissions/$permissionId',
        authenticated: true,
      );
    } on ApiException {
      rethrow;
    }
  }

  // Получить список запросов (для админа)
  Future<List<SeatAccessRequest>> fetchRequests({String? status}) async {
    try {
      final query = <String, dynamic>{};
      if (status != null) query['status'] = status;

      final response = await _client.getJson(
        '/api/seat-access-requests',
        query: query,
        authenticated: true,
      );

      final items = response['requests'] as List<dynamic>? ?? const [];
      return items
          .map((item) => SeatAccessRequest.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  // Получить мои запросы (для продавца)
  Future<List<SeatAccessRequest>> fetchMyRequests() async {
    try {
      final response = await _client.getJson(
        '/api/seat-access-requests/my',
        authenticated: true,
      );

      final items = response['requests'] as List<dynamic>? ?? const [];
      return items
          .map((item) => SeatAccessRequest.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  // Создать запрос доступа
  Future<SeatAccessRequest> createRequest({
    required int excursionId,
    required String excursionDate,
    required int seatNumber,
    String? reason,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/seat-access-requests',
        body: {
          'excursion_id': excursionId,
          'excursion_date': excursionDate,
          'seat_number': seatNumber,
          if (reason != null) 'reason': reason,
        },
        authenticated: true,
      );

      final requestData = response['request'] as Map<String, dynamic>;
      return SeatAccessRequest.fromJson(requestData);
    } on ApiException {
      rethrow;
    }
  }

  // Одобрить запрос
  Future<void> approveRequest(int requestId) async {
    try {
      await _client.postJson(
        '/api/seat-access-requests/$requestId/approve',
        authenticated: true,
      );
    } on ApiException {
      rethrow;
    }
  }

  // Отклонить запрос
  Future<void> rejectRequest(int requestId) async {
    try {
      await _client.postJson(
        '/api/seat-access-requests/$requestId/reject',
        authenticated: true,
      );
    } on ApiException {
      rethrow;
    }
  }
}

