import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../models/user.dart' as app;

class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;
  app.User? _cachedUser;

  Future<app.User?> loadPersistedUser() async {
    if (_client.auth.currentSession == null) {
      return null;
    }
    return fetchCurrentUser();
  }

  Future<app.User?> signIn(String email, String password) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) {
        return null;
      }
      return fetchCurrentUser();
    } on AuthException catch (error) {
      throw ApiException(error.message, 401);
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
    _cachedUser = null;
  }

  Future<app.User?> fetchCurrentUser() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      return null;
    }

    try {
      final row = await _client
          .from('profiles')
          .select('id,name,email,color,role_id,app_roles(name)')
          .eq('auth_user_id', authUser.id)
          .single();
      final role = row['app_roles'] as Map<String, dynamic>?;
      _cachedUser = app.User(
        id: (row['id'] as num).toInt(),
        name: row['name'] as String? ?? '',
        email: row['email'] as String? ?? authUser.email ?? '',
        role: role?['name'] as String? ?? '',
        roleId: (row['role_id'] as num?)?.toInt() ?? 0,
        isSuperUser: (row['role_id'] as num?)?.toInt() == 1,
        color: row['color'] as String?,
      );
      return _cachedUser;
    } on PostgrestException catch (error) {
      throw ApiException(error.message, 500);
    }
  }
}
