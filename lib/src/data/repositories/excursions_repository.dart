import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';
import '../models/excursion.dart';
import '../models/excursion_photo.dart';

class ExcursionsRepository {
  ExcursionsRepository(this._client);

  final ApiClient _client;

  Future<List<Excursion>> fetchExcursions({
    bool includePast = false,
    String? status, // upcoming | past | all
  }) async {
    final query = <String, dynamic>{};
    if (includePast) {
      query['include_past'] = true;
    }
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final response = await _client.getJson(
      '/api/excursions',
      authenticated: true,
      query: query.isEmpty ? null : query,
    );
    final data = response['data'] as List<dynamic>?;
    if (data == null) {
      return const [];
    }
    return data
        .map((json) => Excursion.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<Excursion?> fetchExcursion(int id,
      {bool includeBookingDetails = false}) async {
    final query = <String, dynamic>{};
    if (includeBookingDetails) {
      query['include_booking_details'] = true;
    }
    final response = await _client.getJson(
      '/api/excursions/$id',
      authenticated: true,
      query: query.isEmpty ? null : query,
    );
    final data = response['data'];
    if (data == null) {
      return null;
    }
    return Excursion.fromJson(data as Map<String, dynamic>);
  }

  Future<List<ExcursionPhoto>> fetchExcursionPhotos(int id) async {
    final response = await _client.getJson(
      '/api/excursions/$id/photos',
      authenticated: true,
    );
    final data = response['data'] as List<dynamic>?;
    if (data == null) {
      return const [];
    }

    return data
        .map((json) => ExcursionPhoto.fromJson(json as Map<String, dynamic>))
        .where((photo) => photo.imageUrl.isNotEmpty)
        .toList();
  }

  Future<Excursion> createExcursion({
    required String title,
    required String description,
    required DateTime dateTime,
    required double price,
    required int maxSeats,
    required bool isActive,
  }) async {
    final response = await _client.postJson(
      '/api/excursions',
      authenticated: true,
      body: {
        'title': title,
        'description': description,
        'date_time': dateTime.toIso8601String(),
        'price': price,
        'max_seats': maxSeats,
        'is_active': isActive,
      },
    );
    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
          'Неверный ответ сервера при создании экскурсии');
    }
    return Excursion.fromJson(data);
  }

  Future<Excursion> updateTariffs({
    required int excursionId,
    required Map<String, dynamic> prices,
    Excursion? currentExcursion,
  }) async {
    // Если prices уже содержит Map<String, dynamic> для каждого типа, используем как есть
    // Иначе (старый формат Map<String, double>) конвертируем
    final pricesData = <String, Map<String, dynamic>>{};

    for (final entry in prices.entries) {
      if (entry.value is Map<String, dynamic>) {
        // Новый формат: уже содержит все поля
        pricesData[entry.key] = entry.value as Map<String, dynamic>;
      } else if (entry.value is double || entry.value is int) {
        // Старый формат: только цена, нужно получить комиссии
        Excursion? fetchedExcursion =
            currentExcursion ?? await fetchExcursion(excursionId);
        if (fetchedExcursion == null) {
          throw const FormatException('Экскурсия не найдена');
        }
        final tariff = fetchedExcursion.tariffs[entry.key];
        pricesData[entry.key] = {
          'price': entry.value,
          'price_without_entry': entry.value,
          'price_with_entry': entry.value,
          'seller_commission_percent': tariff?.sellerCommissionPercent ?? 10.0,
          'partner_commission_percent':
              tariff?.partnerCommissionPercent ?? 10.0,
        };
      }
    }

    final response = await _client.putJson(
      '/api/excursions/$excursionId/prices',
      authenticated: true,
      body: {
        'prices': pricesData,
      },
    );

    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
          'Неверный ответ сервера при обновлении тарифов');
    }

    return Excursion.fromJson(data);
  }

  Future<Excursion> updateStaffPrices({
    required int excursionId,
    required List<Map<String, dynamic>> staffPrices,
  }) async {
    final response = await _client.putJson(
      '/api/excursions/$excursionId/staff-prices',
      authenticated: true,
      body: {
        'staff_prices': staffPrices,
      },
    );

    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
          'Неверный ответ сервера при обновлении цен персонала');
    }

    return Excursion.fromJson(data);
  }

  Future<Excursion> updateActualAmount({
    required int excursionId,
    required double? actualAmount,
  }) async {
    final response = await _client.putJson(
      '/api/excursions/$excursionId/actual-amount',
      authenticated: true,
      body: {
        'actual_amount': actualAmount,
      },
    );

    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
        'Неверный ответ сервера при обновлении фактической суммы',
      );
    }

    return Excursion.fromJson(data);
  }

  Future<Excursion> addUnscheduledDate({
    required int excursionId,
    required DateTime dateTime,
  }) async {
    final response = await _client.postJson(
      '/api/excursions/$excursionId/unscheduled-date',
      authenticated: true,
      body: {
        'date_time': dateTime.toIso8601String(),
      },
    );

    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
          'Неверный ответ сервера при добавлении внеплановой даты');
    }

    return Excursion.fromJson(data);
  }

  Future<Excursion> deleteUnscheduledDate({
    required int excursionId,
    required int dateId,
  }) async {
    final response = await _client.deleteJson(
      '/api/excursions/$excursionId/unscheduled-date/$dateId',
      authenticated: true,
    );

    final data = response['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException(
          'Неверный ответ сервера при удалении внеплановой даты');
    }

    return Excursion.fromJson(data);
  }

  Future<List<CancelledExcursionDate>> fetchCancelledDates() async {
    final response = await _client.getJson(
      '/api/excursions/cancelled-dates',
      authenticated: true,
    );

    final data = response['data'] as List<dynamic>?;
    if (data == null) {
      return const [];
    }

    return data
        .map((json) =>
            CancelledExcursionDate.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelExcursionDate({
    required int excursionId,
    required DateTime dateTime,
  }) async {
    await _client.postJson(
      '/api/excursions/$excursionId/cancel-date',
      authenticated: true,
      body: {
        'date_time': dateTime.toIso8601String(),
      },
    );
  }

  Future<void> restoreExcursionDate({
    required int excursionId,
    required int cancelledDateId,
  }) async {
    await _client.deleteJson(
      '/api/excursions/$excursionId/cancel-date/$cancelledDateId',
      authenticated: true,
    );
  }
}

class CancelledExcursionDate {
  CancelledExcursionDate({
    required this.id,
    required this.excursionId,
    required this.excursionTitle,
    required this.dateTime,
    required this.date,
    required this.time,
    required this.createdAt,
  });

  final int id;
  final int excursionId;
  final String excursionTitle;
  final DateTime dateTime;
  final String date;
  final String time;
  final DateTime createdAt;

  factory CancelledExcursionDate.fromJson(Map<String, dynamic> json) {
    return CancelledExcursionDate(
      id: json['id'] as int,
      excursionId: json['excursion_id'] as int,
      excursionTitle: json['excursion_title'] as String,
      dateTime: DateTime.parse(json['date_time'] as String),
      date: json['date'] as String,
      time: json['time'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
