import 'package:booking_app/src/core/api/api_client.dart';
import 'package:booking_app/src/core/api/api_exception.dart';
import 'package:booking_app/src/data/repositories/seat_permission_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class TestTokenProvider implements TokenProvider {
  @override
  Future<String?> getToken() async => 'test-token';
  @override
  Future<void> saveToken(String token) async {}
  @override
  Future<void> clearToken() async {}
}

void main() {
  test('access requests load without a separate connectivity request', () async {
    final paths = <String>[];
    final client = ApiClient.create(client: MockClient((request) async {
      paths.add(request.url.path);
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.queryParameters['status'], 'pending');
      return http.Response('{"requests":[]}', 200);
    }))..configure(baseUrl: 'https://example.test/functions/v1/api',
        tokenProvider: TestTokenProvider());
    expect(await SeatPermissionRepository(client).fetchRequests(status: 'pending'), isEmpty);
    expect(paths, ['/functions/v1/api/api/seat-access-requests']);
  });

  test('preserves server error rather than reporting no internet', () async {
    final client = ApiClient.create(client: MockClient((_) async =>
        http.Response('{"message":"Service unavailable"}', 503)))
      ..configure(baseUrl: 'https://example.test/functions/v1/api',
          tokenProvider: TestTokenProvider());
    await expectLater(SeatPermissionRepository(client).fetchRequests(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 503)));
  });
}
