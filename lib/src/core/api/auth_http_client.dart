import 'dart:async';

import 'package:http/http.dart' as http;

/// Bound small Auth/profile requests, including response body delivery.
class AuthHttpClient extends http.BaseClient {
  AuthHttpClient({http.Client? inner, this.timeout = const Duration(seconds: 10)})
      : _inner = inner ?? http.Client();

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!request.url.path.startsWith('/auth/v1/') &&
        request.url.path != '/rest/v1/profiles') {
      return _inner.send(request);
    }
    final abort = Completer<void>();
    final timer = Timer(timeout, abort.complete);
    try {
      final copy = http.AbortableRequest(request.method, request.url,
          abortTrigger: abort.future)
        ..headers.addAll(request.headers)
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection;
      final response = await (() async {
        copy.bodyBytes = await request.finalize().toBytes();
        return http.Response.fromStream(await _inner.send(copy));
      })().timeout(timeout);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers, contentLength: response.bodyBytes.length,
        request: request, reasonPhrase: response.reasonPhrase,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
    } on http.RequestAbortedException {
      throw TimeoutException('Auth request timed out', timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    } finally {
      timer.cancel();
    }
  }

  @override
  void close() => _inner.close();
}
