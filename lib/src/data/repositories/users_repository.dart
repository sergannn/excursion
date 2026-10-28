import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/api_helpers.dart';
import '../models/user_role_info.dart';
import '../models/user_summary.dart';

class UsersRepository {
  UsersRepository(this._client);

  final ApiClient _client;

  Future<List<UserSummary>> fetchUsers() async {
    try {
      // Запрашиваем больше пользователей за раз, чтобы получить всех
      final response = await _client.getJson(
        '/api/users',
        query: {'per_page': 100},
        authenticated: true,
      );
      final items = response['users'] as List<dynamic>? ?? const [];
      return items
          .map((item) => UserSummary.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  Future<List<UserRoleInfo>> fetchRoles() async {
    try {
      final response =
          await _client.getJson('/api/users/roles', authenticated: true);
      final items = response['roles'] as List<dynamic>? ?? const [];
      return items
          .map((item) => UserRoleInfo.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  Future<UserSummary> createUser({
    required String name,
    required String email,
    required String password,
    required int roleId,
  }) async {
    final response = await _client.postJson(
      '/api/users',
      authenticated: true,
      body: {
        'name': name,
        'email': email,
        'password': password,
        'role_id': roleId,
      },
    );

    final userJson = response['user'] as Map<String, dynamic>;
    return UserSummary.fromJson(userJson);
  }

  Future<void> deleteUser(int userId) async {
    await _client.deleteJson(
      '/api/users/$userId',
      authenticated: true,
    );
  }

  Future<void> updateUserColor(int userId, String? color) async {
    await _client.putJson(
      '/api/users/$userId/color',
      authenticated: true,
      body: {
        'color': color,
      },
    );
  }
}
