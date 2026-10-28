import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/api_helpers.dart';
import '../models/seller.dart';
import '../models/sale.dart';

class SettlementsRepository {
  SettlementsRepository(this._client);

  final ApiClient _client;

  /// Получить список продавцов
  Future<List<Seller>> fetchSellers() async {
    try {
      final response = await _client.getJson(
        '/api/settlements/sellers',
        authenticated: true,
      );
      final items = response['sellers'] as List<dynamic>? ?? const [];
      return items
          .map((item) => Seller.fromJson(item as Map<String, dynamic>))
          .toList();
    } on ApiException {
      rethrow;
    }
  }

  /// Получить продажи продавца с фильтрацией по датам
  Future<SellerSalesResponse> fetchSellerSales(
    int sellerId, {
    DateTime? dateFrom,
    DateTime? dateTo,
    bool settled = false, // false = не рассчитанные, true = рассчитанные
  }) async {
    try {
      final query = <String, String>{
        'settled': settled.toString(),
      };
      if (dateFrom != null) {
        query['date_from'] = dateFrom.toIso8601String().split('T')[0];
      }
      if (dateTo != null) {
        query['date_to'] = dateTo.toIso8601String().split('T')[0];
      }

      final response = await _client.getJson(
        '/api/settlements/sellers/$sellerId/sales',
        query: query,
        authenticated: true,
      );

      return SellerSalesResponse.fromJson(response);
    } on ApiException {
      rethrow;
    }
  }

  /// Создать расчет
  Future<Settlement> createSettlement({
    required int sellerId,
    required List<int> bookingIds,
    String? notes,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    try {
      final body = <String, dynamic>{
        'seller_id': sellerId,
        'booking_ids': bookingIds,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        if (dateFrom != null)
          'date_from': dateFrom.toIso8601String().split('T')[0],
        if (dateTo != null)
          'date_to': dateTo.toIso8601String().split('T')[0],
      };

      final response = await _client.postJson(
        '/api/settlements',
        body: body,
        authenticated: true,
      );

      return Settlement.fromJson(response['settlement'] as Map<String, dynamic>);
    } on ApiException {
      rethrow;
    }
  }

  /// Удалить конкретную продажу из расчета
  Future<Map<String, dynamic>> removeBookingFromSettlement({
    required int settlementId,
    required int bookingId,
  }) async {
    try {
      final response = await _client.postJson(
        '/api/settlements/$settlementId/remove-booking',
        body: {
          'booking_id': bookingId,
        },
        authenticated: true,
      );
      return response;
    } on ApiException {
      rethrow;
    }
  }

  /// Получить статус дней для календаря
  Future<Map<String, String>> fetchCalendarStatus(int sellerId) async {
    try {
      final response = await _client.getJson(
        '/api/settlements/sellers/$sellerId/calendar-status',
        authenticated: true,
      );
      final daysStatus = response['days_status'] as Map<String, dynamic>? ?? {};
      return daysStatus.map((key, value) => MapEntry(key, value as String));
    } on ApiException {
      rethrow;
    }
  }

  /// Отменить расчет полностью (удалить)
  Future<void> deleteSettlement(int settlementId) async {
    try {
      await _client.deleteJson(
        '/api/settlements/$settlementId',
        authenticated: true,
      );
    } on ApiException {
      rethrow;
    }
  }
}

class SellerSalesResponse {
  const SellerSalesResponse({
    required this.seller,
    required this.totalAmount,
    required this.sales,
    this.periodStats,
  });

  final Seller seller;
  final double totalAmount;
  final List<Sale> sales;
  final PeriodStats? periodStats;

  factory SellerSalesResponse.fromJson(Map<String, dynamic> json) {
    return SellerSalesResponse(
      seller: Seller.fromJson(json['seller'] as Map<String, dynamic>),
      totalAmount: (json['total_amount'] as num).toDouble(),
      sales: (json['sales'] as List<dynamic>)
          .map((item) => Sale.fromJson(item as Map<String, dynamic>))
          .toList(),
      periodStats: json['period_stats'] != null
          ? PeriodStats.fromJson(json['period_stats'] as Map<String, dynamic>)
          : null,
    );
  }
}

class PeriodStats {
  const PeriodStats({
    required this.totalSales,
    required this.settledSales,
    required this.unsettledSales,
    required this.totalCount,
    required this.settledCount,
    required this.unsettledCount,
  });

  final double totalSales;
  final double settledSales;
  final double unsettledSales;
  final int totalCount;
  final int settledCount;
  final int unsettledCount;

  factory PeriodStats.fromJson(Map<String, dynamic> json) {
    return PeriodStats(
      totalSales: Settlement._parseDouble(json['total_sales']),
      settledSales: Settlement._parseDouble(json['settled_sales']),
      unsettledSales: Settlement._parseDouble(json['unsettled_sales']),
      totalCount: Settlement._parseInt(json['total_count']),
      settledCount: Settlement._parseInt(json['settled_count']),
      unsettledCount: Settlement._parseInt(json['unsettled_count']),
    );
  }
}

class Settlement {
  const Settlement({
    required this.id,
    required this.sellerId,
    required this.totalAmount,
    required this.settlementDate,
    required this.bookingsCount,
  });

  final int id;
  final int sellerId;
  final double totalAmount;
  final DateTime settlementDate;
  final int bookingsCount;

  factory Settlement.fromJson(Map<String, dynamic> json) {
    return Settlement(
      id: _parseInt(json['id']),
      sellerId: _parseInt(json['seller_id']),
      totalAmount: _parseDouble(json['total_amount']),
      settlementDate: DateTime.parse(json['settlement_date'] as String),
      bookingsCount: _parseInt(json['bookings_count']),
    );
  }
  
  static int _parseInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.parse(value);
    throw FormatException('Cannot parse int from: $value');
  }
  
  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.parse(value);
    throw FormatException('Cannot parse double from: $value');
  }
}
