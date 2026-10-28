import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Условные импорты для веба
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_mobile.dart' as web;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FlutterLocalNotificationsPlugin? _notifications;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    // Для веба используем Web Notifications API
    if (kIsWeb) {
      await _initializeWeb();
    } else {
      // Для мобильных платформ используем flutter_local_notifications
      await _initializeMobile();
    }

    _initialized = true;
  }

  Future<void> _initializeWeb() async {
    await web.WebNotificationHelper.initialize();
  }

  Future<void> _initializeMobile() async {
    _notifications = FlutterLocalNotificationsPlugin();

    // Создаем канал уведомлений для Android
    const androidChannel = AndroidNotificationChannel(
      'assignments_channel',
      'Назначения на экскурсии',
      description: 'Уведомления о новых назначениях на экскурсии',
      importance: Importance.high,
    );

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    final initialized = await _notifications!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    if (initialized == true) {
      // Создаем канал для Android 8.0+
      await _notifications!
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    // Обработка нажатия на уведомление
    debugPrint('Notification tapped: ${response.payload}');
  }

  Future<void> showAssignmentNotification({
    required String title,
    required String body,
    int? excursionId,
  }) async {
    if (!_initialized) {
      await initialize();
    }

    if (kIsWeb) {
      await _showWebNotification(title: title, body: body);
    } else {
      await _showMobileNotification(
        title: title,
        body: body,
        excursionId: excursionId,
      );
    }
  }

  Future<void> _showWebNotification({
    required String title,
    required String body,
  }) async {
    await web.WebNotificationHelper.showNotification(
      title: title,
      body: body,
    );
  }

  Future<void> _showMobileNotification({
    required String title,
    required String body,
    int? excursionId,
  }) async {
    if (_notifications == null) {
      await _initializeMobile();
    }

    const androidDetails = AndroidNotificationDetails(
      'assignments_channel',
      'Назначения на экскурсии',
      channelDescription: 'Уведомления о новых назначениях на экскурсии',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications!.show(
      excursionId ?? DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: excursionId?.toString(),
    );
  }

  Future<void> cancelAll() async {
    if (kIsWeb) {
      // В вебе нет прямого способа отменить все уведомления
      // Они автоматически исчезают через некоторое время
      return;
    } else {
      await _notifications?.cancelAll();
    }
  }
}
