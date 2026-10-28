import 'package:collection/collection.dart';

import 'stop.dart';

class BookingGroup {
  const BookingGroup({
    required this.excursion,
    required this.bookings,
  });

  final BookingExcursion excursion;
  final List<BookingItem> bookings;

  factory BookingGroup.fromList(List<BookingItem> items) {
    final first = items.first;
    return BookingGroup(
      excursion: first.excursion,
      bookings: items,
    );
  }
}

class BookingExcursion {
  const BookingExcursion({
    required this.id,
    required this.title,
    required this.date,
    required this.time,
    required this.dateTime,
    required this.price,
    this.maxSeats,
    this.scheduleByDate = const [],
  });

  final int id;
  final String title;
  final DateTime date;
  final String time;
  final DateTime dateTime;
  final double price;
  final int? maxSeats;
  final List<ScheduleDate> scheduleByDate;

  factory BookingExcursion.fromJson(Map<String, dynamic> json) {
    final dateTimeStr = json['date_time'] as String?;
    DateTime dateTime;
    DateTime date;
    String time = '';

    if (dateTimeStr != null && dateTimeStr.isNotEmpty) {
      dateTime = DateTime.parse(dateTimeStr);
      date = DateTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          dateTime.microsecond);
      time = json['time'] as String? ?? dateTime.toString().substring(11, 16);
    } else {
      // Если date_time null, используем текущую дату как fallback
      dateTime = DateTime.now();
      date = DateTime.now();
    }

    // Парсим schedule_by_date если есть
    final scheduleByDateJson = json['schedule_by_date'] as List<dynamic>?;
    final scheduleByDate = scheduleByDateJson == null
        ? <ScheduleDate>[]
        : scheduleByDateJson
            .map((item) => ScheduleDate.fromJson(item as Map<String, dynamic>))
            .toList();

    return BookingExcursion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String,
      date: date,
      time: time,
      dateTime: dateTime,
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      maxSeats: json['max_seats'] as int?,
      scheduleByDate: scheduleByDate,
    );
  }
}

class ScheduleDate {
  const ScheduleDate({
    required this.date,
    required this.dateTime,
    required this.weekday,
    required this.weekdayName,
    required this.time,
  });

  final String date; // Y-m-d
  final DateTime dateTime;
  final int weekday;
  final String weekdayName;
  final String time;

  factory ScheduleDate.fromJson(Map<String, dynamic> json) {
    return ScheduleDate(
      date: json['date'] as String,
      dateTime: DateTime.parse(json['date_time'] as String),
      weekday: (json['weekday'] as num?)?.toInt() ?? 0,
      weekdayName: json['weekday_name'] as String? ?? '',
      time: json['time'] as String? ?? '',
    );
  }
}

class BookingItem {
  const BookingItem({
    required this.id,
    required this.excursion,
    required this.seat,
    required this.price,
    this.debt,
    required this.customerName,
    required this.customerPhone,
    this.comment,
    required this.passengerType,
    required this.stop,
    required this.bookedAt,
    this.bookedBy,
    this.bookedByName,
    this.weekday,
    this.time,
  });

  final int id;
  final BookingExcursion excursion;
  final BookingSeat seat;
  final double price;
  final double? debt;
  final String customerName;
  final String customerPhone;
  final String? comment;
  final PassengerType passengerType;
  final Stop? stop;
  final DateTime bookedAt;
  final int? bookedBy; // ID пользователя, который создал бронирование
  final String? bookedByName; // Имя пользователя, который создал бронирование
  final int? weekday; // 1-7: Понедельник-Воскресенье
  final String? time; // Время в формате HH:mm

  factory BookingItem.fromJson(Map<String, dynamic> json) {
    BookingSeat parseSeat() {
      final seatJson = json['bus_seat'];
      if (seatJson is Map<String, dynamic>) {
        return BookingSeat.fromJson(seatJson);
      }
      final seatNumberRaw = json['seat_number'];
      final seatNumber = seatNumberRaw is int
          ? seatNumberRaw
          : int.tryParse(seatNumberRaw?.toString() ?? '') ?? 0;
      final seatId = json['bus_seat_id'] as int? ?? 0;
      return BookingSeat(id: seatId, seatNumber: seatNumber);
    }

    DateTime parseBookedAt() {
      final raw = json['booked_at'] ?? json['created_at'];
      if (raw is String && raw.isNotEmpty) {
        return DateTime.parse(raw);
      }
      return DateTime.now();
    }

    return BookingItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      excursion:
          BookingExcursion.fromJson(json['excursion'] as Map<String, dynamic>),
      seat: parseSeat(),
      price: double.tryParse(json['price']?.toString() ?? '') ?? 0,
      debt: json['debt'] != null
          ? double.tryParse(json['debt'].toString())
          : null,
      customerName: json['customer_name'] as String? ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      comment: json['comment'] as String?,
      weekday: (json['weekday'] as num?)?.toInt(),
      time: json['time'] as String?,
      passengerType:
          PassengerTypeX.fromJson(json['passenger_type'] as String? ?? ''),
      stop: json['stop'] == null
          ? null
          : Stop.fromJson(json['stop'] as Map<String, dynamic>),
      bookedAt: parseBookedAt(),
      bookedBy: json['booked_by'] as int?,
      bookedByName: json['booked_by_name'] as String?,
    );
  }
}

class BookingSeat {
  const BookingSeat({
    required this.id,
    required this.seatNumber,
  });

  final int id;
  final int seatNumber;

  factory BookingSeat.fromJson(Map<String, dynamic> json) {
    return BookingSeat(
      id: (json['id'] as num?)?.toInt() ?? 0,
      seatNumber: json['seat_number'] is int
          ? json['seat_number'] as int
          : int.tryParse(json['seat_number'].toString()) ?? 0,
    );
  }
}

class BookingResponse {
  const BookingResponse({
    required this.message,
    this.errors,
    this.bookings,
  });

  final String message;
  final List<String>? errors;
  final List<Map<String, dynamic>>? bookings;

  factory BookingResponse.fromJson(Map<String, dynamic> json) {
    return BookingResponse(
      message: json['message'] as String? ?? '',
      errors: (json['errors'] as List<dynamic>?)?.cast<String>(),
      bookings: (json['bookings'] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .toList(),
    );
  }

  /// Получает ID первого бронирования (для генерации PDF)
  int? get firstBookingId {
    if (bookings == null || bookings!.isEmpty) return null;
    return bookings!.first['id'] as int?;
  }
}

enum PassengerType { adult, child, senior, disabled, special, concession }

extension PassengerTypeX on PassengerType {
  String get apiValue => name;

  String get label {
    switch (this) {
      case PassengerType.adult:
        return 'Взрослый';
      case PassengerType.child:
        return 'Детский';
      case PassengerType.senior:
        return 'Пенсионер';
      case PassengerType.disabled:
        return 'Инвалид';
      case PassengerType.special:
        return 'Спеццена';
      case PassengerType.concession:
        return 'Льготный';
    }
  }

  /// Возвращает true, если тип пассажира требует входной билет
  bool get requiresEntry {
    switch (this) {
      case PassengerType.adult:
      case PassengerType.child:
      case PassengerType.senior:
      case PassengerType.disabled:
        return true; // Со входными
      case PassengerType.concession:
      case PassengerType.special:
        return false; // Без входных
    }
  }

  static PassengerType fromJson(String value) {
    return PassengerType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => PassengerType.adult,
    );
  }
}

List<BookingGroup> groupBookingsByExcursion(List<BookingItem> items) {
  // Группируем по excursion.id И по дате экскурсии (dateTime),
  // чтобы бронирования одной экскурсии на разные даты были в разных группах
  final grouped = groupBy(items, (item) {
    // Используем комбинацию excursion.id и даты (только дата, без времени) для группировки
    final dateKey = DateTime(
      item.excursion.dateTime.year,
      item.excursion.dateTime.month,
      item.excursion.dateTime.day,
    );
    return '${item.excursion.id}_${dateKey.millisecondsSinceEpoch}';
  });
  return grouped.values.map(BookingGroup.fromList).toList();
}

/// Бронирования уже имеют конкретную дату - не разворачиваем их
/// Просто возвращаем как есть, используя date_time из бронирования
List<BookingItem> expandBookingsByDates(List<BookingItem> items) {
  // У бронирования всегда есть конкретная дата из выбранной экскурсии
  // Не нужно разворачивать по расписанию - просто возвращаем как есть
  return items;
}
