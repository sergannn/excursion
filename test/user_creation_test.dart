import 'package:flutter_test/flutter_test.dart';
import 'package:booking_app/src/data/repositories/users_repository.dart';
import 'package:booking_app/src/core/api/api_client.dart';
import 'package:booking_app/src/core/api/api_exception.dart';
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
  // URL тестового API
  const apiUrl = 'https://excursion.panfilius.ru';

  late ApiClient apiClient;
  late TestTokenProvider tokenProvider;
  late UsersRepository repository;
  late AuthRepository authRepository;

  setUpAll(() {
    tokenProvider = TestTokenProvider();
    apiClient = ApiClient.create();
    apiClient.configure(
      baseUrl: apiUrl,
      tokenProvider: tokenProvider,
    );
    repository = UsersRepository(apiClient);
    authRepository = AuthRepository(apiClient);
  });

  group('User Creation and Fetch Tests (Real API)', () {
    test(
        'createUser returns user with password and then fetchUsers includes it',
        () async {
      // Авторизуемся как админ
      try {
        final user =
            await authRepository.signIn('admin@excursion.ru', 'password');
        expect(user, isNotNull,
            reason: 'Должна быть успешная авторизация админа');
      } on ApiException catch (e) {
        if (e.statusCode == 401 || e.statusCode == 404) {
          fail('Не удалось авторизоваться как админ: ${e.message}');
        }
        rethrow;
      }

      // Создаем уникального пользователя
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testEmail = 'testuser$timestamp@test.com';
      final testName = 'Test User $timestamp';
      final testPassword = 'testpassword123';

      // Получаем роль "Продавец" (обычно role_id = 2)
      const sellerRoleId = 2;

      // Создаем пользователя
      final created = await repository.createUser(
        name: testName,
        email: testEmail,
        password: testPassword,
        roleId: sellerRoleId,
      );

      expect(created.email, testEmail,
          reason: 'Email созданного пользователя должен совпадать');
      expect(created.name, testName,
          reason: 'Имя созданного пользователя должно совпадать');
      expect(created.password, testPassword,
          reason: 'Пароль должен быть возвращен при создании');
      expect(created.roleId, sellerRoleId, reason: 'Role ID должен совпадать');

      // Ждем немного, чтобы сервер обработал запрос
      await Future.delayed(const Duration(milliseconds: 500));

      // Получаем список пользователей
      final users = await repository.fetchUsers();

      // Проверяем, что новый пользователь есть в списке
      expect(users.any((u) => u.email == testEmail), isTrue,
          reason: 'Новый пользователь должен быть в списке после создания');

      final newUser = users.firstWhere((u) => u.email == testEmail);
      expect(newUser.name, testName, reason: 'Имя должно совпадать');
      expect(newUser.email, testEmail, reason: 'Email должен совпадать');
      expect(newUser.roleId, sellerRoleId, reason: 'Role ID должен совпадать');

      // Удаляем тестового пользователя
      try {
        await repository.deleteUser(created.id);
        print('Тестовый пользователь удален: $testEmail');
      } catch (e) {
        print('Не удалось удалить тестового пользователя: $e');
        // Игнорируем ошибки удаления, но выводим предупреждение
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
