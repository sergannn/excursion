/// Заглушка для мобильных платформ
/// Веб-специфичный код не загружается на мобильных платформах
class WebNotificationHelper {
  static Future<void> initialize() async {
    // Ничего не делаем на мобильных платформах
  }

  static Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    // Ничего не делаем на мобильных платформах
  }
}








