import 'dart:async';

import 'package:booking_app/src/core/api/auth_http_client.dart';
import 'package:booking_app/src/data/repositories/auth_repository.dart';
import 'package:booking_app/src/core/api/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HangingClient extends http.BaseClient {
  bool aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortable = request as http.Abortable;
    await abortable.abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }
}

void main() {
  test('preserves auth request and response', () async {
    final client = AuthHttpClient(inner: MockClient((request) async {
      expect(request.body, '{"test":true}');
      expect(request.headers['apikey'], 'test-key');
      return http.Response('{"access_token":"test-token"}', 200,
          headers: {'content-type': 'application/json'});
    }));
    final response = await client.post(Uri.parse('https://example.test/auth/v1/token'),
        headers: {'apikey': 'test-key'}, body: '{"test":true}');
    expect(response.statusCode, 200);
    expect(response.body, contains('test-token'));
    client.close();
  });

  test('aborts stalled auth and profile requests', () async {
    for (final path in ['/auth/v1/token', '/rest/v1/profiles']) {
      final inner = HangingClient();
      final client = AuthHttpClient(inner: inner,
          timeout: const Duration(milliseconds: 20));
      await expectLater(client.get(Uri.parse('https://example.test$path')),
          throwsA(isA<TimeoutException>()));
      await Future<void>.delayed(Duration.zero);
      expect(inner.aborted, isTrue);
      client.close();
    }
  });

  test('transport timeout is not reported as an incorrect password', () async {
    final client = SupabaseClient('https://example.test', 'test-key',
        httpClient: AuthHttpClient(inner: HangingClient(),
            timeout: const Duration(milliseconds: 20)));
    final repository = AuthRepository(client: client);
    await expectLater(repository.signIn('test@example.test', 'test-password'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 0)));
    await client.dispose();
  });
}
