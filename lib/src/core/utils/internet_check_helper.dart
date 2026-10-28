import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/internet_connection_service.dart';

/// Вспомогательный класс для проверки интернета перед важными действиями
class InternetCheckHelper {
  /// Проверить наличие интернета и показать сообщение, если его нет
  /// Возвращает true, если интернет есть, false - если нет
  static Future<bool> checkInternetWithMessage(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final service = ref.read(internetConnectionServiceProvider);
      final hasInternet = await service.hasInternet;
      
      if (!hasInternet) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Нет подключения к интернету. Проверьте соединение и попробуйте снова.',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      // В случае ошибки считаем, что интернета нет
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось проверить подключение к интернету'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return false;
    }
  }
}
