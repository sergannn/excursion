class ApiException implements Exception {
  ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  /// Проверка, является ли это ошибкой отсутствия интернета
  bool get isNoInternet => statusCode == null || statusCode == 0;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, message: $message)';
}
