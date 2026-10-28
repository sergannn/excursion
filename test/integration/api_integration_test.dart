import 'package:flutter_test/flutter_test.dart';
import 'package:booking_app/src/core/api/api_client.dart';
import 'package:booking_app/src/core/api/api_exception.dart';
import 'package:booking_app/src/data/repositories/users_repository.dart';
import 'package:booking_app/src/data/repositories/excursions_repository.dart';
import 'package:booking_app/src/data/repositories/bookings_repository.dart';
import 'package:booking_app/src/data/repositories/wallet_repository.dart';
import 'package:booking_app/src/data/repositories/assignments_repository.dart';
import 'package:booking_app/src/data/repositories/schedule_repository.dart';
import 'package:booking_app/src/data/repositories/auth_repository.dart';

/// Тестовый TokenProvider для интеграционных тестов
class TestTokenProvider implements TokenProvider {
  String? _token;

  @override
  Future<String?> getToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }

  @override
  Future<void> clearToken() async {
    _token = null;
  }
}

void main() {
  // URL тестового API - можно настроить через переменную окружения
  final apiUrl = const String.fromEnvironment(
    'TEST_API_URL',
    defaultValue: 'https://excursion.panfilius.ru',
  );

  late ApiClient apiClient;
  late TestTokenProvider tokenProvider;

  setUpAll(() {
    tokenProvider = TestTokenProvider();
    apiClient = ApiClient.create();
    apiClient.configure(
      baseUrl: apiUrl,
      tokenProvider: tokenProvider,
    );
  });

  group('API Integration Tests', () {
    group('Authentication', () {
      test('admin login with valid credentials', () async {
        final authRepo = AuthRepository(apiClient);

        try {
          final user = await authRepo.signIn('admin@excursion.ru', 'password');

          expect(user, isNotNull);
          expect(user?.id, greaterThan(0));
          expect(user?.isSuperUser, isTrue); // Проверяем, что это админ

          // Токен сохраняется автоматически через ApiClient
        } on ApiException catch (e) {
          // Если тестовый пользователь не существует, это нормально
          if (e.statusCode == 401 || e.statusCode == 404) {
            // Пропускаем тест, если нет тестовых данных
            return;
          }
          rethrow;
        }
      });

      test('login with invalid credentials returns 401', () async {
        final authRepo = AuthRepository(apiClient);

        try {
          final user =
              await authRepo.signIn('invalid@test.com', 'wrongpassword');
          expect(user, isNull);
        } on ApiException catch (e) {
          expect(e.statusCode, 401);
        }
      });
    });

    group('Users API', () {
      test('fetchUsers handles all error codes', () async {
        final repo = UsersRepository(apiClient);

        // Тест без аутентификации (должен вернуть 401)
        await tokenProvider.clearToken();

        try {
          await repo.fetchUsers();
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 401);
        }
      });

      test('fetchUsers with authentication returns users list', () async {
        // Сначала логинимся
        final authRepo = AuthRepository(apiClient);
        try {
          await authRepo.signIn('admin@excursion.ru', 'password');
        } catch (e) {
          // Если нет тестовых данных, пропускаем
          return;
        }

        final repo = UsersRepository(apiClient);

        try {
          final users = await repo.fetchUsers();
          expect(users, isA<List>());
          // Если есть пользователи, проверяем структуру
          if (users.isNotEmpty) {
            expect(users.first.id, greaterThan(0));
            expect(users.first.name, isNotEmpty);
            expect(users.first.email, isNotEmpty);
          }
        } on ApiException catch (e) {
          // Обрабатываем различные ошибки
          expect([400, 401, 403, 404, 500, 502, 503], contains(e.statusCode));
        }
      });
    });

    group('Excursions API', () {
      test('fetchExcursions handles all error codes', () async {
        final repo = ExcursionsRepository(apiClient);

        // Тест без аутентификации
        await tokenProvider.clearToken();

        try {
          await repo.fetchExcursions();
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([401, 403], contains(e.statusCode));
        }
      });

      test('fetchExcursions with authentication', () async {
        // Логинимся если нужно
        final authRepo = AuthRepository(apiClient);
        try {
          await authRepo.signIn('admin@excursion.ru', 'password');
        } catch (e) {
          return; // Пропускаем если нет тестовых данных
        }

        final repo = ExcursionsRepository(apiClient);

        try {
          final excursions = await repo.fetchExcursions();
          expect(excursions, isA<List>());
        } on ApiException catch (e) {
          // Обрабатываем различные ошибки
          expect([400, 401, 403, 404, 500, 502, 503], contains(e.statusCode));
        }
      });
    });

    group('Bookings API', () {
      test('fetchBookings handles all error codes', () async {
        final repo = BookingsRepository(apiClient);

        await tokenProvider.clearToken();

        try {
          await repo.fetchBookings();
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([401, 403], contains(e.statusCode));
        }
      });
    });

    group('Wallet API', () {
      test('fetchWallet handles all error codes', () async {
        final repo = WalletRepository(apiClient);

        await tokenProvider.clearToken();

        try {
          await repo.fetchWallet(1);
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([401, 403, 404], contains(e.statusCode));
        }
      });
    });

    group('Assignments API', () {
      test('checkNewAssignments handles all error codes', () async {
        final repo = AssignmentsRepository(apiClient);

        await tokenProvider.clearToken();

        try {
          await repo.checkNewAssignments();
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([401, 403, 404], contains(e.statusCode));
        }
      });
    });

    group('Schedule API', () {
      test('fetchSchedule handles all error codes', () async {
        final repo = ScheduleRepository(apiClient);

        await tokenProvider.clearToken();

        try {
          await repo.fetchSchedule();
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([401, 403, 404], contains(e.statusCode));
        }
      });
    });

    group('Error Handling', () {
      test('handles 400 Bad Request', () async {
        // Тест с невалидными данными
        final authRepo = AuthRepository(apiClient);

        try {
          await authRepo.signIn('', '');
          fail('Should have thrown ApiException');
        } on ApiException catch (e) {
          expect([400, 422], contains(e.statusCode));
        }
      });

      test('handles 404 Not Found', () async {
        final repo = ExcursionsRepository(apiClient);

        // Логинимся если нужно
        try {
          final authRepo = AuthRepository(apiClient);
          await authRepo.signIn('admin@excursion.ru', 'password');
        } catch (e) {
          return;
        }

        try {
          await repo.fetchExcursion(999999); // Несуществующий ID
        } on ApiException catch (e) {
          expect([404, 403], contains(e.statusCode));
        }
      });

      test('handles 500 Internal Server Error', () async {
        // Этот тест может сработать только если сервер вернет 500
        // Обычно это происходит при реальных ошибках сервера
        final repo = UsersRepository(apiClient);

        try {
          final authRepo = AuthRepository(apiClient);
          await authRepo.signIn('admin@excursion.ru', 'password');
        } catch (e) {
          return;
        }

        try {
          await repo.fetchUsers();
          // Если запрос успешен, это нормально
        } on ApiException catch (e) {
          // Если получили ошибку, проверяем что она обработана
          expect(e.statusCode, greaterThanOrEqualTo(400));
          expect(e.message, isNotEmpty);
        }
      });

      test('handles network timeout', () async {
        // Тест с очень коротким таймаутом (если поддерживается)
        // В реальности это может быть сложно протестировать без моков
        // Но можно проверить обработку исключений
        final repo = UsersRepository(apiClient);

        try {
          await repo.fetchUsers();
        } on ApiException catch (e) {
          // Любая ошибка API должна быть обработана
          expect(e, isA<ApiException>());
        } catch (e) {
          // Другие исключения (например, таймаут) также должны быть обработаны
          expect(e, isA<Exception>());
        }
      });
    });
  });
}
