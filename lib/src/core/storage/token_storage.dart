import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';

class TokenStorage implements TokenProvider {
  TokenStorage._();

  static final TokenStorage instance = TokenStorage._();

  static const _tokenKey = 'auth_token';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> getToken() async {
    return _prefs?.getString(_tokenKey);
  }

  @override
  Future<void> saveToken(String token) async {
    await _prefs?.setString(_tokenKey, token);
  }

  @override
  Future<void> clearToken() async {
    await _prefs?.remove(_tokenKey);
  }
}
