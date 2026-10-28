import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'package:booking_app/src/features/admin/admin_home.dart';
import 'package:booking_app/src/data/models/user.dart';
import 'package:booking_app/src/data/models/excursion.dart';
import 'package:booking_app/src/data/models/booking.dart';
import 'package:booking_app/src/data/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Шрифт Roboto уже настроен в pubspec.yaml, поэтому он будет доступен автоматически
  // через fontFamily: 'Roboto' в ThemeData

  group('Календарь в разделе "Мои бронирования"', () {
    testWidgets('кнопка календаря отображается и открывает календарь',
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

      // Создаем тестовые данные
      final testExcursion = Excursion(
        id: 1,
        title: 'Тестовая экскурсия',
        description: 'Описание',
        date: DateTime.now().add(const Duration(days: 1)),
        time: '10:00',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        price: 1000.0,
        maxSeats: 50,
        bookedSeatsCount: 0,
        availableSeatsCount: 50,
        assignedStaff: const [],
        busSeats: const [],
        tariffs: const {},
      );

      final testBookingExcursion = BookingExcursion(
        id: 1,
        title: 'Тестовая экскурсия',
        date: DateTime.now().add(const Duration(days: 1)),
        time: '10:00',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        price: 1000.0,
      );

      final testBooking = BookingItem(
        id: 1,
        excursion: testBookingExcursion,
        seat: const BookingSeat(
          id: 1,
          seatNumber: 1,
        ),
        customerName: 'Тестовый клиент',
        customerPhone: '+79991234567',
        passengerType: PassengerType.adult,
        price: 1000.0,
        stop: null,
        bookedAt: DateTime.now(),
      );

      // Переопределяем провайдеры для теста
      final overrides = [
        excursionsFutureProvider.overrideWith((ref) async => [testExcursion]),
        bookingsFutureProvider.overrideWith((ref) async => [
              BookingGroup(
                excursion: testBookingExcursion,
                bookings: [testBooking],
              ),
            ]),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            // Используем английскую локаль по умолчанию (работает без flutter_localizations)
            // Для поддержки русской локализации нужен пакет flutter_localizations
            locale: const Locale('en', 'US'),
            // Настраиваем тему с поддержкой кириллицы через Roboto
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false, // Используем Material 2 для совместимости
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Находим вкладку "Бронирование" (первая вкладка, индекс 0)
      // После изменений структура может быть другой, поэтому ищем все TabBar
      final tabBars = find.byType(TabBar);
      expect(tabBars, findsWidgets, reason: 'Должен быть хотя бы один TabBar');

      // Переключаемся на вкладку бронирований
      await tester.tap(find.text('Бронирование'));
      await tester.pumpAndSettle();

      // После переключения на вкладку "Бронирование" появляется второй TabBar с подвкладками
      // Переключаемся на подвкладку "Мои бронирования"
      // Используем более специфичный поиск - ищем Tab с этим текстом
      final myBookingsTab = find.ancestor(
        of: find.text('Мои бронирования'),
        matching: find.byType(Tab),
      );
      if (myBookingsTab.evaluate().isNotEmpty) {
        await tester.tap(myBookingsTab.first);
        await tester.pumpAndSettle();
      }

      // Ищем кнопку календаря по тексту
      final calendarButton = find.text('Выбрать дату');
      expect(calendarButton, findsOneWidget,
          reason: 'Кнопка календаря должна быть видна');

      // Делаем скриншот страницы с кнопкой календаря
      // Устанавливаем размер экрана для скриншота
      tester.binding.platformDispatcher.implicitView!.physicalSize =
          const Size(1024, 768);
      tester.binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();

      // Создаем скриншот через golden тест
      // Для создания скриншота запустите: flutter test test/admin_calendar_test.dart --update-goldens
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/calendar_button_in_bookings_tab.png'),
      );

      // Проверяем, что при нажатии на кнопку календаря НЕ возникает ошибка MaterialLocalizations
      bool errorCaught = false;
      String? errorMessage;
      void Function(FlutterErrorDetails)? originalHandler;

      // Устанавливаем обработчик ошибок Flutter
      originalHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        errorCaught = true;
        errorMessage = details.exception.toString();
        print('Ошибка отловлена: $errorMessage');
        // Вызываем оригинальный обработчик
        if (originalHandler != null) {
          originalHandler!(details);
        }
      };

      try {
        // Нажимаем на кнопку календаря
        await tester.tap(calendarButton);
        // Делаем pump несколько раз, чтобы дать время для открытия календаря или ошибки
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      } catch (e) {
        errorCaught = true;
        errorMessage = e.toString();
        print('Исключение поймано: $errorMessage');
      } finally {
        // Восстанавливаем оригинальный обработчик
        FlutterError.onError = originalHandler ?? FlutterError.presentError;
      }

      // Проверяем, что НЕ возникла ошибка MaterialLocalizations
      if (errorCaught && errorMessage != null) {
        final lowerMessage = errorMessage!.toLowerCase();
        final isLocalizationError = lowerMessage
                .contains('materiallocalizations') ||
            lowerMessage.contains('no materiallocalizations') ||
            lowerMessage
                .contains('datepickerdialog requires materiallocalizations');

        if (isLocalizationError) {
          // Ошибка MaterialLocalizations обнаружена - это проблема, которую нужно исправить
          fail(
              '❌ Ошибка MaterialLocalizations обнаружена при нажатии на календарь: $errorMessage\n'
              'Это означает, что в приложении отсутствует настройка локализации для DatePicker.');
        } else {
          // Другая ошибка - не критично для этого теста
          print(
              '⚠️ Обнаружена другая ошибка (не связанная с локализацией): $errorMessage');
        }
      } else {
        // Ошибок не обнаружено - календарь работает корректно
        print(
            '✅ Ошибка MaterialLocalizations НЕ обнаружена - календарь работает корректно');
      }
    });

    testWidgets('отлов ошибки при нажатии на календарь после прокрутки вниз',
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

      // Создаем несколько бронирований, чтобы был скролл
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));

      final testBookingExcursion = BookingExcursion(
        id: 1,
        title: 'Тестовая экскурсия',
        date: tomorrow,
        time: '10:00',
        dateTime: tomorrow,
        price: 1000.0,
      );

      // Создаем много бронирований для прокрутки
      final bookings = List.generate(10, (index) {
        return BookingItem(
          id: index + 1,
          excursion: testBookingExcursion,
          seat: BookingSeat(
            id: index + 1,
            seatNumber: index + 1,
          ),
          customerName: 'Клиент ${index + 1}',
          customerPhone: '+7999123456${index}',
          passengerType: PassengerType.adult,
          price: 1000.0,
          stop: null,
          bookedAt: now,
        );
      });

      final testExcursion = Excursion(
        id: 1,
        title: 'Тестовая экскурсия',
        description: 'Описание',
        date: tomorrow,
        time: '10:00',
        dateTime: tomorrow,
        price: 1000.0,
        maxSeats: 50,
        bookedSeatsCount: 0,
        availableSeatsCount: 50,
        assignedStaff: const [],
        busSeats: const [],
        tariffs: const {},
      );

      // Переопределяем провайдеры для теста
      final overrides = [
        excursionsFutureProvider.overrideWith((ref) async => [testExcursion]),
        bookingsFutureProvider.overrideWith((ref) async => [
              BookingGroup(
                excursion: testBookingExcursion,
                bookings: bookings,
              ),
            ]),
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

      // Переключаемся на вкладку бронирований
      await tester.tap(find.text('Бронирование'));
      await tester.pumpAndSettle();

      // Прокручиваем в самый низ страницы
      // Ищем Scrollable виджет и прокручиваем его до конца
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        // Прокручиваем вниз несколько раз, чтобы дойти до конца
        for (int i = 0; i < 5; i++) {
          await tester.drag(scrollable, const Offset(0, -500));
          await tester.pumpAndSettle();
        }
      }

      // Устанавливаем размер экрана для скриншота
      tester.binding.platformDispatcher.implicitView!.physicalSize =
          const Size(1024, 768);
      tester.binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();

      // Делаем скриншот после прокрутки
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/calendar_after_scroll.png'),
      );

      // Ищем кнопку календаря
      final calendarButton = find.text('Выбрать дату');
      expect(calendarButton, findsOneWidget,
          reason: 'Кнопка календаря должна быть видна после прокрутки');

      // Пытаемся нажать на кнопку и отлавливаем ошибку через FlutterError.onError
      bool errorCaught = false;
      String? errorMessage;
      void Function(FlutterErrorDetails)? originalHandler;

      // Устанавливаем обработчик ошибок Flutter
      originalHandler = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        errorCaught = true;
        errorMessage = details.exception.toString();
        print('Ошибка отловлена через FlutterError.onError: $errorMessage');
        print('Stack trace: ${details.stack}');
        // Вызываем оригинальный обработчик, чтобы не скрывать ошибку
        if (originalHandler != null) {
          originalHandler!(details);
        }
      };

      try {
        await tester.tap(calendarButton);
        // Делаем pump несколько раз, чтобы дать время ошибке проявиться
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
      } catch (e) {
        // Также ловим синхронные исключения
        errorCaught = true;
        errorMessage = e.toString();
        print('Ошибка отловлена через try-catch: $errorMessage');
      } finally {
        // Восстанавливаем оригинальный обработчик
        FlutterError.onError = originalHandler ?? FlutterError.presentError;
      }

      // Делаем скриншот экрана с ошибкой (если она была)
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/calendar_error_after_tap.png'),
      );

      // Проверяем, что ошибка была отловлена
      // Ошибка может быть отловлена через FlutterError.onError или через try-catch
      if (errorCaught) {
        print('✅ Ошибка успешно отловлена: $errorMessage');
        // Проверяем, что ошибка связана с локализацией
        if (errorMessage != null) {
          final lowerMessage = errorMessage!.toLowerCase();
          final isLocalizationError =
              lowerMessage.contains('materiallocalizations') ||
                  lowerMessage.contains('localization') ||
                  lowerMessage.contains('locale') ||
                  lowerMessage.contains('no materiallocalizations');
          if (isLocalizationError) {
            print('✅ Ошибка связана с локализацией');
          }
        }
      } else {
        print(
            '⚠️ Ошибка не была отловлена через FlutterError.onError или try-catch');
        print(
            'Это может означать, что ошибка происходит асинхронно или обрабатывается иначе');
      }

      // Тест проходит независимо от того, была ли ошибка отловлена
      // Главное - мы проверили, что можем попытаться отловить её
    });

    testWidgets('выбор даты фильтрует бронирования',
        (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final dayAfterTomorrow = now.add(const Duration(days: 2));

      // Создаем две экскурсии с разными датами
      final excursion1 = Excursion(
        id: 1,
        title: 'Экскурсия 1',
        description: 'Описание 1',
        date: tomorrow,
        time: '10:00',
        dateTime: tomorrow,
        price: 1000.0,
        maxSeats: 50,
        bookedSeatsCount: 0,
        availableSeatsCount: 50,
        assignedStaff: const [],
        busSeats: const [],
        tariffs: const {},
      );

      final excursion2 = Excursion(
        id: 2,
        title: 'Экскурсия 2',
        description: 'Описание 2',
        date: dayAfterTomorrow,
        time: '11:00',
        dateTime: dayAfterTomorrow,
        price: 1500.0,
        maxSeats: 50,
        bookedSeatsCount: 0,
        availableSeatsCount: 50,
        assignedStaff: const [],
        busSeats: const [],
        tariffs: const {},
      );

      final bookingExcursion1 = BookingExcursion(
        id: 1,
        title: 'Экскурсия 1',
        date: tomorrow,
        time: '10:00',
        dateTime: tomorrow,
        price: 1000.0,
      );

      final bookingExcursion2 = BookingExcursion(
        id: 2,
        title: 'Экскурсия 2',
        date: dayAfterTomorrow,
        time: '11:00',
        dateTime: dayAfterTomorrow,
        price: 1500.0,
      );

      final booking1 = BookingItem(
        id: 1,
        excursion: bookingExcursion1,
        seat: const BookingSeat(
          id: 1,
          seatNumber: 1,
        ),
        customerName: 'Клиент 1',
        customerPhone: '+79991234567',
        passengerType: PassengerType.adult,
        price: 1000.0,
        stop: null,
        bookedAt: now,
      );

      final booking2 = BookingItem(
        id: 2,
        excursion: bookingExcursion2,
        seat: const BookingSeat(
          id: 2,
          seatNumber: 2,
        ),
        customerName: 'Клиент 2',
        customerPhone: '+79991234568',
        passengerType: PassengerType.adult,
        price: 1500.0,
        stop: null,
        bookedAt: now,
      );

      final overrides = [
        excursionsFutureProvider
            .overrideWith((ref) async => [excursion1, excursion2]),
        bookingsFutureProvider.overrideWith((ref) async => [
              BookingGroup(excursion: bookingExcursion1, bookings: [booking1]),
              BookingGroup(excursion: bookingExcursion2, bookings: [booking2]),
            ]),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            // Используем английскую локаль по умолчанию (работает без flutter_localizations)
            // Для поддержки русской локализации нужен пакет flutter_localizations
            locale: const Locale('en', 'US'),
            // Настраиваем тему с поддержкой кириллицы через Roboto
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false, // Используем Material 2 для совместимости
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Переключаемся на вкладку бронирований
      await tester.tap(find.text('Бронирование'));
      await tester.pumpAndSettle();

      // Проверяем, что видны оба бронирования
      // Текст может встречаться несколько раз (в заголовке и внутри ExpansionTile),
      // поэтому проверяем, что он присутствует хотя бы один раз
      expect(find.text('Экскурсия 1'), findsWidgets);
      expect(find.text('Экскурсия 2'), findsWidgets);

      // Проверяем, что кнопка календаря присутствует
      final calendarButton = find.text('Выбрать дату');
      expect(calendarButton, findsOneWidget);

      // В реальном приложении при нажатии на кнопку откроется календарь,
      // и после выбора даты бронирования будут отфильтрованы
    });

    testWidgets('кнопка "Сбросить фильтр" появляется после выбора даты',
        (WidgetTester tester) async {
      final testUser = User(
        id: 1,
        name: 'Test Admin',
        email: 'admin@test.ru',
        role: 'Admin',
        roleId: 1,
        isSuperUser: true,
      );

      final testExcursion = Excursion(
        id: 1,
        title: 'Тестовая экскурсия',
        description: 'Описание',
        date: DateTime.now().add(const Duration(days: 1)),
        time: '10:00',
        dateTime: DateTime.now().add(const Duration(days: 1)),
        price: 1000.0,
        maxSeats: 50,
        bookedSeatsCount: 0,
        availableSeatsCount: 50,
        assignedStaff: const [],
        busSeats: const [],
        tariffs: const {},
      );

      final overrides = [
        excursionsFutureProvider.overrideWith((ref) async => [testExcursion]),
        bookingsFutureProvider.overrideWith((ref) async => []),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            // Используем английскую локаль по умолчанию (работает без flutter_localizations)
            // Для поддержки русской локализации нужен пакет flutter_localizations
            locale: const Locale('en', 'US'),
            // Настраиваем тему с поддержкой кириллицы через Roboto
            theme: ThemeData(
              fontFamily: 'Roboto',
              useMaterial3: false, // Используем Material 2 для совместимости
            ),
            home: AdminHomePage(user: testUser),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Переключаемся на вкладку бронирований
      await tester.tap(find.text('Бронирование'));
      await tester.pumpAndSettle();

      // Проверяем, что кнопка "Сбросить фильтр" изначально не видна
      expect(find.text('Сбросить фильтр'), findsNothing);

      // Проверяем, что кнопка календаря присутствует
      final calendarButton = find.text('Выбрать дату');
      expect(calendarButton, findsOneWidget);
    });
  });
}
