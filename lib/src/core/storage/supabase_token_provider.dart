import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';

class SupabaseTokenProvider implements TokenProvider {
  const SupabaseTokenProvider();

  @override
  Future<String?> getToken() async {
    return Supabase.instance.client.auth.currentSession?.accessToken;
  }

  @override
  Future<void> saveToken(String token) async {
    // Supabase Auth owns and refreshes its session tokens.
  }

  @override
  Future<void> clearToken() => Supabase.instance.client.auth.signOut();
}
