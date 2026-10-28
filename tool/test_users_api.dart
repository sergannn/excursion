import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> main() async {
  const baseUrl = 'https://excursion.panfilius.ru';

  Future<void> log(String message) async =>
      stdout.writeln('[API TEST] $message');

  final client = http.Client();

  try {
    await log('Logging in...');
    final loginUri = Uri.parse('$baseUrl/api/auth/login');
    final loginRequest = http.Request('POST', loginUri)
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      })
      ..followRedirects = false
      ..body = jsonEncode({
        'email': 'admin@excursion.ru',
        'password': 'password',
      });

    final loginResponse = await client.send(loginRequest);

    final loginBody = await loginResponse.stream.bytesToString();
    if (loginResponse.statusCode != 200) {
      await log('Login failed: ${loginResponse.statusCode} $loginBody');
      return;
    }

    final loginJson = jsonDecode(loginBody) as Map<String, dynamic>;
    final token = loginJson['token'] as String?;
    if (token == null) {
      await log('No token in login response: $loginBody');
      return;
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    await log('Fetching roles...');
    final rolesResponse = await client.get(
      Uri.parse('$baseUrl/api/users/roles'),
      headers: headers,
    );

    if (rolesResponse.statusCode != 200) {
      await log('Roles request failed: ${rolesResponse.statusCode} ${rolesResponse.body}');
      return;
    }

    final rolesJson = jsonDecode(rolesResponse.body) as Map<String, dynamic>;
    final roles = rolesJson['roles'] as List<dynamic>? ?? [];
    await log('Roles: $roles');
    if (roles.isEmpty) {
      await log('No roles available; aborting user creation.');
      return;
    }

    final roleId = (roles.first as Map<String, dynamic>)['id'] as int;

    await log('Creating test user...');
    final createResponse = await client.post(
      Uri.parse('$baseUrl/api/users'),
      headers: headers,
      body: jsonEncode({
        'name': 'Тестовый Пользователь',
        'email': 'test.user+${DateTime.now().millisecondsSinceEpoch}@example.com',
        'password': 'password123',
        'role_id': roleId,
      }),
    );

    await log('Create status: ${createResponse.statusCode}');
    await log('Create body: ${createResponse.body}');
  } catch (error, stackTrace) {
    await log('Unhandled error: $error');
    await log('$stackTrace');
  } finally {
    client.close();
  }
}
