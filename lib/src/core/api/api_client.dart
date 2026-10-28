import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import '../services/internet_connection_service.dart';

abstract class TokenProvider {
  Future<String?> getToken();
  Future<void> saveToken(String token);
  Future<void> clearToken();
}

class ApiClient {
  ApiClient._internal() : _client = http.Client();

  static final ApiClient instance = ApiClient._internal();

  static ApiClient create() => ApiClient._internal();

  final http.Client _client;
  late String _baseUrl;
  late TokenProvider _tokenProvider;
  InternetConnectionService? _internetService;

  /// Получает base URL (публичный метод)
  String get baseUrl => _baseUrl;

  void configure({
    required String baseUrl,
    required TokenProvider tokenProvider,
    InternetConnectionService? internetService,
  }) {
    _baseUrl = baseUrl;
    _tokenProvider = tokenProvider;
    _internetService = internetService;
  }

  /// Установить сервис проверки интернета (можно вызвать после configure)
  void setInternetService(InternetConnectionService service) {
    _internetService = service;
  }

  /// Проверка интернета перед запросом
  Future<void> _checkInternetBeforeRequest() async {
    if (_internetService != null) {
      final hasInternet = await _internetService!.hasInternet;
      if (!hasInternet) {
        throw ApiException(
          'Нет подключения к интернету. Проверьте соединение и попробуйте снова.',
          0, // Специальный код для отсутствия интернета
        );
      }
    }
  }

  Uri _buildUri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse(_baseUrl);
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final fullPath = uri.path.endsWith('/')
        ? '${uri.path}$normalizedPath'
        : '${uri.path}/$normalizedPath';
    
    // Обрабатываем query параметры, включая массивы
    if (query == null || query.isEmpty) {
      return uri.replace(path: fullPath);
    }
    
    // Строим query строку вручную для поддержки массивов
    final queryParts = <String>[];
    query.forEach((key, value) {
      if (value is List) {
        // Для массивов создаем несколько параметров с ключом key[]
        // Это будет обработано как ids[]=1&ids[]=2 в URL
        for (var item in value) {
          queryParts.add('${Uri.encodeComponent(key)}[]=${Uri.encodeComponent(item.toString())}');
        }
      } else {
        queryParts.add('${Uri.encodeComponent(key)}=${Uri.encodeComponent(value.toString())}');
      }
    });
    
    final queryString = queryParts.join('&');
    return uri.replace(
      path: fullPath,
      query: queryString.isEmpty ? null : queryString,
    );
  }

  Map<String, String> _baseHeaders([Map<String, String>? extra]) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (extra != null) ...extra,
    };
  }

  Future<http.Response> get(
    String path, {
    Map<String, dynamic>? query,
    bool authenticated = false,
    Map<String, String>? headers,
  }) async {
    await _checkInternetBeforeRequest();
    final baseHeaders = await _headers(authenticated: authenticated);
    final allHeaders = {
      ...baseHeaders,
      if (headers != null) ...headers,
    };
    final response =
        await _client.get(_buildUri(path, query), headers: allHeaders);
    _throwIfNeeded(response);
    return response;
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    await _checkInternetBeforeRequest();
    final headers = await _headers(authenticated: authenticated);
    final response = await _client.post(
      _buildUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    _throwIfNeeded(response);
    return response;
  }

  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    await _checkInternetBeforeRequest();
    final headers = await _headers(authenticated: authenticated);
    final response = await _client.put(
      _buildUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    _throwIfNeeded(response);
    return response;
  }

  Future<http.Response> delete(
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = false,
  }) async {
    await _checkInternetBeforeRequest();
    final headers = await _headers(authenticated: authenticated);
    final response = await _client.delete(
      _buildUri(path),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    _throwIfNeeded(response);
    return response;
  }

  Future<Map<String, String>> _headers({required bool authenticated}) async {
    final headers = _baseHeaders();
    if (authenticated) {
      final token = await _tokenProvider.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  Future<void> storeToken(String token) => _tokenProvider.saveToken(token);

  Future<void> clearToken() => _tokenProvider.clearToken();

  Future<String?> readStoredToken() => _tokenProvider.getToken();

  void _throwIfNeeded(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    String message = 'Request failed with status ${response.statusCode}';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      
      // Для ошибок валидации (422) Laravel возвращает ошибки в поле 'errors'
      if (response.statusCode == 422 && decoded.containsKey('errors')) {
        final errors = decoded['errors'] as Map<String, dynamic>?;
        if (errors != null && errors.isNotEmpty) {
          // Берем первое сообщение об ошибке
          final firstErrorKey = errors.keys.first;
          final firstErrorMessages = errors[firstErrorKey] as List<dynamic>?;
          if (firstErrorMessages != null && firstErrorMessages.isNotEmpty) {
            message = firstErrorMessages.first.toString();
          }
        }
      } else {
        // Для других ошибок ищем сообщение в поле 'message'
        final bodyMessage = decoded['message'] as String?;
        if (bodyMessage != null && bodyMessage.isNotEmpty) {
          message = bodyMessage;
        }
      }
    } catch (_) {}
    throw ApiException(message, response.statusCode);
  }
}
