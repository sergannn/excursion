import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';
import '../models/booking.dart';

class SeatBooking {
  const SeatBooking({
    required this.seatNumber,
    required this.passengerType,
    this.withEntry = false,
    this.price,
    this.debt,
    this.customerName,
    this.customerPhone,
    this.comment,
  });

  final int seatNumber;
  final PassengerType passengerType;
  final bool withEntry;
  final double? price;
  final double? debt;
  final String? customerName; // Имя пассажира для этого места
  final String? customerPhone; // Телефон пассажира для этого места
  final String? comment; // Комментарий к конкретному месту

  Map<String, dynamic> toJson() {
    return {
      'seat_number': seatNumber,
      'passenger_type': passengerType.apiValue,
      'with_entry': withEntry,
      if (price != null) 'price': price,
      if (debt != null) 'debt': debt,
      if (customerName != null) 'customer_name': customerName,
      if (customerPhone != null) 'customer_phone': customerPhone,
      if (comment != null && comment!.trim().isNotEmpty)
        'comment': comment!.trim(),
    };
  }
}

class BookSeatPayload {
  BookSeatPayload({
    required this.excursionId,
    required this.customerName,
    required this.customerPhone,
    required this.stopId,
    // Дата и время бронирования
    this.weekday,
    this.time,
    this.excursionDate,
    // Новый формат: массив мест с типами пассажиров
    this.seats,
    // Старый формат (для обратной совместимости)
    this.seatNumbers,
    this.passengerType,
    // Для админов: бронирование от лица продавца
    this.bookedById,
  }) : assert(
          (seats != null && seats.isNotEmpty) ||
              (seatNumbers != null &&
                  seatNumbers.isNotEmpty &&
                  passengerType != null),
          'Either seats or seatNumbers with passengerType must be provided',
        );

  final int excursionId;
  final String customerName;
  final String customerPhone;
  final int stopId;
  final int? weekday; // 1-7: Понедельник-Воскресенье
  final String? time; // Время в формате HH:mm
  final String? excursionDate; // Конкретная дата экскурсии (YYYY-MM-DD)

  // Новый формат: массив мест с типами пассажиров
  final List<SeatBooking>? seats;

  // Старый формат (для обратной совместимости)
  final List<int>? seatNumbers;
  final PassengerType? passengerType;

  // Для админов: бронирование от лица продавца
  final int? bookedById;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'excursion_id': excursionId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'stop_id': stopId,
    };

    // Добавляем дату и время, если указаны
    if (weekday != null) {
      json['weekday'] = weekday;
    }
    if (time != null) {
      json['time'] = time;
    }
    if (excursionDate != null) {
      json['excursion_date'] = excursionDate;
    }

    // Используем новый формат, если доступен
    if (seats != null && seats!.isNotEmpty) {
      json['seats'] = seats!.map((s) => s.toJson()).toList();
    } else if (seatNumbers != null &&
        seatNumbers!.isNotEmpty &&
        passengerType != null) {
      // Старый формат для обратной совместимости
      json['seat_numbers'] = seatNumbers!;
      json['passenger_type'] = passengerType!.apiValue;
    }

    // Добавляем booked_by_id, если указан (для админов)
    if (bookedById != null) {
      json['booked_by_id'] = bookedById;
    }

    return json;
  }
}

class BookingsRepository {
  BookingsRepository(this._client);

  final ApiClient _client;

  Future<List<BookingGroup>> fetchBookings() async {
    final response =
        await _client.getJson('/api/bookings', authenticated: true);
    final items = response['bookings'] as List<dynamic>? ?? const [];
    final bookingItems = items
        .map((item) => BookingItem.fromJson(item as Map<String, dynamic>))
        .toList();
    return groupBookingsByExcursion(bookingItems);
  }

  /// Получить бронирования для водителя/экскурсовода
  /// Возвращает бронирования для экскурсий, на которые назначен пользователь
  Future<List<BookingItem>> fetchDriverBookings() async {
    final response = await _client.getJson(
      '/api/bookings/driver',
      authenticated: true,
    );
    final items = response['bookings'] as List<dynamic>? ?? const [];
    return items
        .map((item) => BookingItem.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<BookingResponse> bookSeats(BookSeatPayload payload) async {
    final response = await _client.postJson(
      '/api/bookings',
      authenticated: true,
      body: payload.toJson(),
    );
    return BookingResponse.fromJson(response);
  }

  Future<void> cancelBooking(int bookingId, {required String reason}) async {
    await _client.deleteJson(
      '/api/bookings/$bookingId',
      authenticated: true,
      body: {
        'reason': reason,
      },
    );
  }

  Future<Map<String, dynamic>> updateBooking({
    required int bookingId,
    String? customerName,
    String? customerPhone,
    String? comment,
    PassengerType? passengerType,
    bool? withEntry,
    double? price,
    double? debt,
    int? stopId,
    bool clearStop = false,
  }) async {
    final body = <String, dynamic>{};

    if (customerName != null) body['customer_name'] = customerName;
    if (customerPhone != null) body['customer_phone'] = customerPhone;
    if (comment != null) body['comment'] = comment;
    if (passengerType != null) body['passenger_type'] = passengerType.apiValue;
    if (withEntry != null) body['with_entry'] = withEntry;
    if (price != null) body['price'] = price;
    if (debt != null) body['debt'] = debt;
    if (clearStop) {
      body['stop_id'] = null;
    } else if (stopId != null) {
      body['stop_id'] = stopId;
    }

    return _client.putJson(
      '/api/bookings/$bookingId',
      authenticated: true,
      body: body,
    );
  }

  /// Получает полный URL для скачивания PDF билета
  String getTicketPdfUrl(int bookingId) {
    // Получаем base URL из ApiClient
    final baseUrl = _client.baseUrl;
    final path = '/api/bookings/$bookingId/ticket-pdf';

    // Если baseUrl заканчивается на /, убираем его
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Строим полный URL
    return '$normalizedBase$path';
  }

  /// Скачивает PDF билет как байты (для сохранения/отправки на мобильных)
  /// Если передан список ID, использует их для генерации PDF со всеми местами
  Future<Uint8List> downloadTicketPdf(int bookingId,
      {List<int>? bookingIds}) async {
    String path = '/api/bookings/$bookingId/ticket-pdf';

    // Если передан список ID, передаем их как query параметры
    Map<String, dynamic>? queryParams;
    if (bookingIds != null && bookingIds.isNotEmpty) {
      // Для Laravel массивы в query параметрах передаются как ids[]=1&ids[]=2
      // Но http пакет требует специальной обработки для массивов
      queryParams = {
        'ids': bookingIds, // Передаем массив напрямую
      };
      print('PDF download: path=$path');
      print(
          'PDF download: bookingIds=$bookingIds (count: ${bookingIds.length})');
      print(
          'PDF download: bookingIds types: ${bookingIds.map((id) => id.runtimeType).toList()}');
    } else {
      print(
          'PDF download: no bookingIds provided, using single booking $bookingId');
    }

    final response = await _client.get(
      path,
      query: queryParams,
      authenticated: true,
      headers: {
        'Accept': 'application/pdf',
      },
    );

    print('PDF download: response status = ${response.statusCode}');
    print('PDF download: response headers = ${response.headers}');

    return Uint8List.fromList(response.bodyBytes);
  }
}
