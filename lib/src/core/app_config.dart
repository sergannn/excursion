import 'supabase_config.dart';

class AppConfig {
  AppConfig._();

  static String get apiBaseUrl => '${SupabaseConfig.url}/functions/v1/api';
}
