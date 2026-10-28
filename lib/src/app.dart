import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/api/api_client.dart';
import 'core/app_config.dart';
import 'core/storage/supabase_token_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/settings_service.dart';
import 'features/common/app_shell.dart';

class BookingAppBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    await initializeDateFormatting('ru_RU');
    await SettingsService.instance.init();
    ApiClient.instance.configure(
      baseUrl: AppConfig.apiBaseUrl,
      tokenProvider: const SupabaseTokenProvider(),
    );
    // Инициализируем сервис уведомлений
    await NotificationService().initialize();
    _initialized = true;
  }
}

class BookingApp extends StatelessWidget {
  const BookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Booking Manager',
        locale: const Locale('ru', 'RU'),
          builder: (context, child) {
          // Добавляем проверку на веб
          if (kIsWeb) {
            return Center(
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 400, // Максимальная ширина для веба
                ),
                child: child,
              ),
            );
          }
          // Для мобильных/десктоп приложений
          return child!;
        },
        home: const AppShell(),
      ),
    );
  }
}
