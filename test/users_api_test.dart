import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:booking_app/src/data/models/user_summary.dart';
import 'package:booking_app/src/data/repositories/users_repository.dart';
import 'package:booking_app/src/core/api/api_exception.dart';
import 'helpers/mock_api_client.dart';

void main() {
  group('Users API Tests', () {
    test('fetchUsers handles successful response with admin password', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          expect(path, '/api/users');
          return {
            'users': [
              {
                'id': 1,
                'name': 'Admin User',
                'email': 'admin@test.com',
                'role': 'Admin',
                'role_id': 1,
                'balance': 0.0,
                'password': 'admin123',
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              },
              {
                'id': 2,
                'name': 'Seller User',
                'email': 'seller@test.com',
                'role': 'Seller',
                'role_id': 2,
                'balance': 1000.50,
                'password': 'seller123',
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              },
            ],
            'pagination': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 15,
              'total': 2,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );

      final users = repository.fetchUsers();
      expect(users, completes);
    });

    test('fetchUsers handles response without password for non-admin', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          return {
            'users': [
              {
                'id': 1,
                'name': 'Seller User',
                'email': 'seller@test.com',
                'role': 'Seller',
                'role_id': 2,
                'balance': 0.0,
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              },
            ],
            'pagination': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 15,
              'total': 1,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );
    });

    test('fetchUsers handles 400 Bad Request error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Неверный запрос', 400);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 401 Unauthorized error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Необходима аутентификация', 401);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 403 Forbidden error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Недостаточно прав', 403);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 404 Not Found error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Ресурс не найден', 404);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 500 Internal Server Error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Ошибка при получении списка пользователей', 500);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 502 Bad Gateway error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Ошибка шлюза', 502);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles 503 Service Unavailable error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw ApiException('Сервис недоступен', 503);
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<ApiException>()),
      );
    });

    test('fetchUsers handles generic Exception', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw Exception('Неожиданная ошибка');
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchUsers handles network timeout error', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          throw TimeoutException('Превышено время ожидания', Duration(seconds: 30));
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('fetchUsers handles malformed response (missing users key)', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          return {
            'pagination': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 15,
              'total': 0,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );

      final users = repository.fetchUsers();
      expect(users, completes);
      users.then((userList) {
        expect(userList, isEmpty);
      });
    });

    test('fetchUsers handles empty users array', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          return {
            'users': [],
            'pagination': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 15,
              'total': 0,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );

      final users = repository.fetchUsers();
      expect(users, completes);
      users.then((userList) {
        expect(userList, isEmpty);
      });
    });

    test('UserSummary.fromJson handles password field correctly', () {
      final jsonWithPassword = {
        'id': 1,
        'name': 'Admin User',
        'email': 'admin@test.com',
        'role': 'Admin',
        'role_id': 1,
        'balance': 0.0,
        'password': 'admin123',
      };

      expect(() => UserSummary.fromJson(jsonWithPassword), returnsNormally);
      final user = UserSummary.fromJson(jsonWithPassword);
      expect(user.id, 1);
      expect(user.name, 'Admin User');
      expect(user.email, 'admin@test.com');
      expect(user.password, 'admin123');
    });

    test('UserSummary.fromJson handles missing password field', () {
      final jsonWithoutPassword = {
        'id': 1,
        'name': 'User',
        'email': 'user@test.com',
        'role': 'Seller',
        'role_id': 2,
        'balance': 0.0,
      };

      expect(
        () => UserSummary.fromJson(jsonWithoutPassword),
        returnsNormally,
      );
      final user = UserSummary.fromJson(jsonWithoutPassword);
      expect(user.id, 1);
      expect(user.password, isNull);
    });

    test('UserSummary.fromJson handles null balance', () {
      final json = {
        'id': 1,
        'name': 'User',
        'email': 'user@test.com',
        'role': 'Seller',
        'role_id': 2,
        'balance': null,
      };

      expect(() => UserSummary.fromJson(json), returnsNormally);
      final user = UserSummary.fromJson(json);
      expect(user.balance, 0.0);
    });

    test('UserSummary.fromJson handles string balance', () {
      final json = {
        'id': 1,
        'name': 'User',
        'email': 'user@test.com',
        'role': 'Seller',
        'role_id': 2,
        'balance': '1000.50',
      };

      expect(() => UserSummary.fromJson(json), returnsNormally);
      final user = UserSummary.fromJson(json);
      expect(user.balance, 1000.50);
    });

    test('fetchUsers handles response with pagination', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          expect(path, '/api/users');
          return {
            'users': List.generate(10, (index) => {
              return {
                'id': index + 1,
                'name': 'User ${index + 1}',
                'email': 'user${index + 1}@test.com',
                'role': 'Seller',
                'role_id': 2,
                'balance': 0.0,
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              };
            }),
            'pagination': {
              'current_page': 1,
              'last_page': 2,
              'per_page': 10,
              'total': 20,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );

      final users = repository.fetchUsers();
      expect(users, completes);
      users.then((userList) {
        expect(userList.length, 10);
      });
    });

    test('fetchUsers handles response with role filtering', () {
      final mockClient = MockApiClient(
        mockGetJson: (path, {query}) {
          expect(path, '/api/users');
          // В реальном API query параметры передаются, но в репозитории они не используются
          return {
            'users': [
              {
                'id': 1,
                'name': 'Driver 1',
                'email': 'driver1@test.com',
                'role': 'Driver',
                'role_id': 3,
                'balance': 0.0,
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              },
              {
                'id': 2,
                'name': 'Driver 2',
                'email': 'driver2@test.com',
                'role': 'Driver',
                'role_id': 3,
                'balance': 0.0,
                'created_at': '2025-01-01T00:00:00Z',
                'updated_at': '2025-01-01T00:00:00Z',
              },
            ],
            'pagination': {
              'current_page': 1,
              'last_page': 1,
              'per_page': 15,
              'total': 2,
            },
          };
        },
      );

      final repository = UsersRepository(mockClient);

      expect(
        () => repository.fetchUsers(),
        returnsNormally,
      );
    });
  });
}

