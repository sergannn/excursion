import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';
import '../storage/token_storage.dart';
import 'settings_service.dart';

/// Провайдер для сервиса проверки интернета
final internetConnectionServiceProvider =
    Provider<InternetConnectionService>((ref) {
  final service = InternetConnectionService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Провайдер для статуса интернета (true = есть интернет, false = нет)
final internetStatusProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(internetConnectionServiceProvider);
  // Убеждаемся, что сервис инициализирован
  ref.onDispose(() {});
  return service.statusStream;
});

/// Сервис для мониторинга интернет-соединения
class InternetConnectionService {
  static const _connectionTimeout = Duration(seconds: 10);
  static const _failuresBeforeOffline = 2;

  final Connectivity _connectivity = Connectivity();
  StreamController<bool>? _statusController;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _checkTimer;
  bool _isDisposed = false;
  int _consecutiveFailures = 0;

  InternetConnectionService() {
    _statusController = StreamController<bool>.broadcast();
    // Сразу отправляем начальное значение (оптимистично предполагаем, что интернет есть)
    _statusController?.add(true);
    _startMonitoring();
  }

  /// Поток статуса интернета
  Stream<bool> get statusStream => _statusController!.stream;

  /// Текущий статус интернета
  Future<bool> get hasInternet => _checkRealConnection();

  void _startMonitoring() {
    // Слушаем изменения подключения
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _checkAndUpdateStatus();
      },
    );

    // Периодически проверяем реальное подключение
    // Используем настройку из SettingsService
    _startPeriodicCheck();

    // Проверяем начальный статус
    _checkAndUpdateStatus();
  }

  void _startPeriodicCheck() {
    // Отменяем предыдущий таймер, если есть
    _checkTimer?.cancel();

    // Получаем интервал из настроек
    final intervalSeconds = SettingsService.instance.internetCheckInterval;

    // Запускаем новый таймер с настройкой из SettingsService
    _checkTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) {
        _checkAndUpdateStatus();
      },
    );
  }

  /// Перезапустить мониторинг с новыми настройками
  void restartMonitoring() {
    if (!_isDisposed) {
      _startPeriodicCheck();
    }
  }

  Future<void> _checkAndUpdateStatus() async {
    if (_isDisposed) return;

    final hasConnection = await _checkRealConnection();
    if (hasConnection) {
      _consecutiveFailures = 0;
      _statusController?.add(true);
      return;
    }

    _consecutiveFailures++;
    if (_consecutiveFailures >= _failuresBeforeOffline) {
      _statusController?.add(false);
    }
  }

  Future<bool> _checkRealConnection() async {
    try {
      // Сначала проверяем тип подключения (не работает надежно на веб)
      if (!kIsWeb) {
        final connectivityResults = await _connectivity.checkConnectivity();
        final hasNetwork = connectivityResults.any(
          (result) => result != ConnectivityResult.none,
        );

        if (!hasNetwork) {
          return false;
        }
      }

      // Проверяем наличие токена
      final token = await TokenStorage.instance.getToken();

      Uri checkUrl;
      Map<String, String> headers = {
        'Accept': 'application/json',
      };

      if (token != null && token.isNotEmpty) {
        // Если есть токен - используем /api/auth/me для проверки
        // Это безопаснее и проверяет не только сервер, но и валидность токена
        checkUrl = Uri.parse('${AppConfig.apiBaseUrl}/api/auth/me');
        headers['Authorization'] = 'Bearer $token';
      } else {
        // Если токена нет - используем публичный health endpoint
        checkUrl = Uri.parse('${AppConfig.apiBaseUrl}/up');
      }

      // Проверяем реальное подключение к нашему API через HTTP запрос
      // Это работает на всех платформах, включая веб
      final response = await http
          .get(checkUrl, headers: headers)
          .timeout(_connectionTimeout);

      // Если получили ответ (даже с ошибкой), значит интернет и сервер доступны
      // Для /me: 200 = OK, 401 = не авторизован (но сервер доступен)
      // Для /up: 200 = OK
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      // Если запрос не прошел (таймаут, нет сети и т.д.), значит интернета нет
      return false;
    }
  }

  void dispose() {
    _isDisposed = true;
    _connectivitySubscription?.cancel();
    _checkTimer?.cancel();
    _statusController?.close();
  }
}
