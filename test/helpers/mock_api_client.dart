import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:booking_app/src/core/api/api_client.dart';
import 'package:booking_app/src/core/api/api_exception.dart';

/// Mock API Client для тестирования
class MockApiClient implements ApiClient {
  final Map<String, dynamic> Function(String, {Map<String, dynamic>? query})?
      mockGetJson;
  final Map<String, dynamic> Function(String, {Map<String, dynamic>? body})?
      mockPostJson;
  final Map<String, dynamic> Function(String, {Map<String, dynamic>? body})?
      mockPutJson;
  final void Function(String)? mockDeleteJson;

  /// Функция для генерации ошибок
  final Exception? Function(String)? errorGenerator;

  MockApiClient({
    this.mockGetJson,
    this.mockPostJson,
    this.mockPutJson,
    this.mockDeleteJson,
    this.errorGenerator,
  });

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    bool authenticated = false,
    Map<String, dynamic>? query,
  }) async {
    if (errorGenerator != null) {
      final error = errorGenerator!(path);
      if (error != null) throw error;
    }
    if (mockGetJson != null) {
      return mockGetJson!(path, query: query);
    }
    throw UnimplementedError('mockGetJson not provided for path: $path');
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    bool authenticated = false,
    Map<String, dynamic>? body,
  }) async {
    if (errorGenerator != null) {
      final error = errorGenerator!(path);
      if (error != null) throw error;
    }
    if (mockPostJson != null) {
      return mockPostJson!(path, body: body);
    }
    throw UnimplementedError('mockPostJson not provided for path: $path');
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    bool authenticated = false,
    Map<String, dynamic>? body,
  }) async {
    if (errorGenerator != null) {
      final error = errorGenerator!(path);
      if (error != null) throw error;
    }
    if (mockPutJson != null) {
      return mockPutJson!(path, body: body);
    }
    throw UnimplementedError('mockPutJson not provided for path: $path');
  }

  @override
  Future<void> deleteJson(
    String path, {
    bool authenticated = false,
  }) async {
    if (errorGenerator != null) {
      final error = errorGenerator!(path);
      if (error != null) throw error;
    }
    if (mockDeleteJson != null) {
      return mockDeleteJson!(path);
    }
    throw UnimplementedError('mockDeleteJson not provided for path: $path');
  }

  @override
  String get baseUrl => 'http://test.com';

  @override
  void configure({
    required String baseUrl,
    required TokenProvider tokenProvider,
  }) {
    // Mock implementation
  }

  @override
  Future<void> clearToken() async {
    // Mock implementation
  }

  @override
  Future<void> storeToken(String token) async {
    // Mock implementation
  }

  @override
  Future<String?> readStoredToken() async {
    return null; // Mock implementation
  }

  @override
  Future<http.Response> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = false,
    Map<String, String>? headers,
  }) async {
    if (mockGetJson != null) {
      final json = await mockGetJson!(path, query: query);
      return http.Response.bytes(
        utf8.encode(jsonEncode(json)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    throw UnimplementedError('get not provided for path: $path');
  }

  @override
  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    if (mockPostJson != null) {
      final json = await mockPostJson!(path, body: body);
      return http.Response.bytes(
        utf8.encode(jsonEncode(json)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    throw UnimplementedError('post not provided for path: $path');
  }

  @override
  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    if (mockPutJson != null) {
      final json = await mockPutJson!(path, body: body);
      return http.Response.bytes(
        utf8.encode(jsonEncode(json)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    throw UnimplementedError('put not provided for path: $path');
  }

  @override
  Future<http.Response> delete(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    if (mockDeleteJson != null) {
      mockDeleteJson!(path);
      return http.Response('', 200);
    }
    throw UnimplementedError('delete not provided for path: $path');
  }
}

/// Вспомогательные функции для создания ошибок
class ErrorHelpers {
  static ApiException apiError(String message, int statusCode) =>
      ApiException(message, statusCode);

  static Exception genericError(String message) => Exception(message);
}

