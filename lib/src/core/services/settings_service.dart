import 'package:shared_preferences/shared_preferences.dart';

/// Сервис для хранения настроек приложения
class SettingsService {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  static const String _keyInternetCheckInterval = 'internet_check_interval_seconds';
  static const int _defaultInternetCheckInterval = 15; // секунд

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Интервал проверки интернета в секундах
  int get internetCheckInterval {
    return _prefs?.getInt(_keyInternetCheckInterval) ?? _defaultInternetCheckInterval;
  }

  Future<void> setInternetCheckInterval(int seconds) async {
    await _prefs?.setInt(_keyInternetCheckInterval, seconds);
  }

  /// Сбросить настройки к значениям по умолчанию
  Future<void> resetToDefaults() async {
    await _prefs?.remove(_keyInternetCheckInterval);
  }
}
