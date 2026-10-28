import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:booking_app/src/features/admin/admin_home.dart';
import 'package:booking_app/src/data/models/user.dart';
import 'package:booking_app/src/data/providers.dart';
import 'package:booking_app/src/core/api/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Вкладка "Статистика" у админа', () {
    testWidgets('отображается общая чистая прибыль',
        (WidgetTester tester) async {
      // Создаем тестового пользователя-админа
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      // Мокируем данные статистики
      final mockStatisticsData = {
        'total_net_profit': 50000.0,
        'statistics': [
          {
            'excursion': {
              'id': 1,
              'title': 'Экскурсия 1',
              'date_time': '2025-11-20T10:00:00',
            },
            'total_revenue': 100000.0,
            'seller_commissions': 10000.0,
            'staff_costs': 40000.0,
            'net_profit': 50000.0,
            'bookings_count': 10,
          },
          {
            'excursion': {
              'id': 2,
              'title': 'Экскурсия 2',
              'date_time': '2025-11-21T14:00:00',
            },
            'total_revenue': 80000.0,
            'seller_commissions': 8000.0,
            'staff_costs': 30000.0,
            'net_profit': 42000.0,
            'bookings_count': 8,
          },
        ],
      };

      // Создаем мок API клиента через создание нового экземпляра
      final mockApiClient = ApiClient.create();
      mockApiClient.configure(
        baseUrl: 'http://localhost',
        tokenProvider: _TestTokenProvider(),
      );

      // Переопределяем провайдер apiClientProvider
      // Но нам нужно мокировать метод get, который используется в getJson
      // Для этого создадим обертку, которая перехватывает вызовы
      final overrides = [
        apiClientProvider.overrideWith((ref) {
          // Возвращаем мок, который переопределяет только метод get
          return _MockApiClientForStatistics(mockStatisticsData);
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false,
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      // Ждем загрузки
      await tester.pumpAndSettle();

      // Переходим на вкладку "Статистика"
      final statisticsTab = find.text('Статистика');
      expect(statisticsTab, findsOneWidget);
      await tester.tap(statisticsTab);
      await tester.pumpAndSettle();

      // Ждем немного больше, чтобы провайдер успел загрузиться
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Проверяем, что отображается "Общая чистая прибыль"
      expect(find.text('Общая чистая прибыль'), findsOneWidget);
      expect(find.text('50000.00 ₽'), findsOneWidget);

      // Проверяем, что отображаются данные по экскурсиям
      expect(find.text('Экскурсия 1'), findsOneWidget);
      expect(find.text('Экскурсия 2'), findsOneWidget);

      // Проверяем, что отображаются финансовые показатели
      expect(find.text('Выручка'), findsNWidgets(2));
      expect(find.text('100000.00 ₽'), findsOneWidget);
      expect(find.text('80000.00 ₽'), findsOneWidget);

      expect(find.text('Комиссии продавцов'), findsNWidgets(2));
      expect(find.text('-10000.00 ₽'), findsOneWidget);
      expect(find.text('-8000.00 ₽'), findsOneWidget);

      expect(find.text('Расходы на персонал'), findsNWidgets(2));
      expect(find.text('-40000.00 ₽'), findsOneWidget);
      expect(find.text('-30000.00 ₽'), findsOneWidget);

      expect(find.text('Чистая прибыль'), findsNWidgets(2));
      expect(find.text('50000.00 ₽'),
          findsNWidgets(2)); // Один раз в общей, один раз в первой экскурсии
      expect(find.text('42000.00 ₽'), findsOneWidget);

      // Проверяем количество бронирований
      expect(find.text('Бронирований: 10'), findsOneWidget);
      expect(find.text('Бронирований: 8'), findsOneWidget);
    });

    testWidgets('отображается состояние загрузки', (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      // Создаем мок с задержкой
      final overrides = [
        apiClientProvider.overrideWith((ref) {
          return _MockApiClientForStatistics(null, delayed: true);
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false,
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pump();

      // Переходим на вкладку "Статистика"
      final statisticsTab = find.text('Статистика');
      await tester.tap(statisticsTab);
      await tester.pump();

      // Проверяем, что отображается индикатор загрузки
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('отображается сообщение об ошибке при ошибке загрузки',
        (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      // Создаем мок с ошибкой
      final overrides = [
        apiClientProvider.overrideWith((ref) {
          return _MockApiClientForStatistics(null,
              error: 'Ошибка загрузки данных');
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false,
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Переходим на вкладку "Статистика"
      final statisticsTab = find.text('Статистика');
      await tester.tap(statisticsTab);
      await tester.pumpAndSettle();

      // Проверяем, что отображается сообщение об ошибке
      expect(find.textContaining('Ошибка загрузки статистики'), findsOneWidget);
      expect(find.text('Повторить'), findsOneWidget);
    });

    testWidgets('отображается сообщение при отсутствии данных',
        (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      // Мокируем пустые данные статистики
      final mockStatisticsData = {
        'total_net_profit': 0.0,
        'statistics': <dynamic>[],
      };

      final overrides = [
        apiClientProvider.overrideWith((ref) {
          return _MockApiClientForStatistics(mockStatisticsData);
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false,
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Переходим на вкладку "Статистика"
      final statisticsTab = find.text('Статистика');
      await tester.tap(statisticsTab);
      await tester.pumpAndSettle();

      // Проверяем, что отображается сообщение об отсутствии данных
      expect(find.text('Нет данных для отображения'), findsOneWidget);
    });

    testWidgets('отображается отрицательная чистая прибыль',
        (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      // Мокируем данные с отрицательной прибылью
      final mockStatisticsData = {
        'total_net_profit': -5000.0,
        'statistics': [
          {
            'excursion': {
              'id': 1,
              'title': 'Убыточная экскурсия',
              'date_time': '2025-11-20T10:00:00',
            },
            'total_revenue': 50000.0,
            'seller_commissions': 5000.0,
            'staff_costs': 50000.0,
            'net_profit': -5000.0,
            'bookings_count': 5,
          },
        ],
      };

      final overrides = [
        apiClientProvider.overrideWith((ref) {
          return _MockApiClientForStatistics(mockStatisticsData);
        }),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            locale: const Locale('en', 'US'),
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false,
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Переходим на вкладку "Статистика"
      final statisticsTab = find.text('Статистика');
      await tester.tap(statisticsTab);
      await tester.pumpAndSettle();

      // Проверяем, что отображается отрицательная прибыль
      expect(
          find.text('-5000.00 ₽'), findsNWidgets(2)); // В общей и в экскурсии
      expect(find.text('Чистая прибыль'), findsOneWidget);
    });
  });
}

// Мок класс для ApiClient, который мокирует только метод get для статистики
// Используем композицию вместо наследования, так как конструктор приватный
class _MockApiClientForStatistics implements ApiClient {
  _MockApiClientForStatistics(this._response,
      {this.delayed = false, this.error}) {
    _baseUrl = 'http://localhost';
    _tokenProvider = _TestTokenProvider();
  }

  final Map<String, dynamic>? _response;
  final bool delayed;
  final String? error;
  late String _baseUrl;
  late TokenProvider _tokenProvider;

  @override
  String get baseUrl => _baseUrl;

  @override
  void configure(
      {required String baseUrl, required TokenProvider tokenProvider}) {
    _baseUrl = baseUrl;
    _tokenProvider = tokenProvider;
  }

  @override
  Future<http.Response> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = false,
    Map<String, String>? headers,
  }) async {
    // Проверяем путь без query параметров
    final cleanPath = path.split('?').first;
    if (cleanPath == '/api/excursions/statistics') {
      if (delayed) {
        await Future.delayed(const Duration(seconds: 1));
        return http.Response(jsonEncode(_response ?? {}), 200);
      }
      if (error != null) {
        // Для ошибок ApiClient._throwIfNeeded выбросит ApiException
        // Но нам нужно вернуть ответ со статусом 500, чтобы _throwIfNeeded его обработал
        return http.Response(jsonEncode({'message': error}), 500);
      }
      if (_response != null) {
        return http.Response(jsonEncode(_response), 200);
      }
    }
    // Для других путей возвращаем пустой ответ, чтобы не падать
    return http.Response('{}', 200);
  }

  // Реализуем остальные методы как заглушки
  @override
  Future<http.Response> post(String path,
      {Map<String, dynamic>? body, bool authenticated = false}) {
    throw UnimplementedError();
  }

  @override
  Future<http.Response> put(String path,
      {Map<String, dynamic>? body, bool authenticated = false}) {
    throw UnimplementedError();
  }

  @override
  Future<http.Response> delete(String path,
      {Map<String, dynamic>? body, bool authenticated = false}) {
    throw UnimplementedError();
  }

  @override
  Future<void> storeToken(String token) => _tokenProvider.saveToken(token);

  @override
  Future<void> clearToken() => _tokenProvider.clearToken();

  @override
  Future<String?> readStoredToken() => _tokenProvider.getToken();
}

// Тестовый TokenProvider
class _TestTokenProvider implements TokenProvider {
  @override
  Future<String?> getToken() async => 'test-token';

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}
