import 'bus_seat.dart';
import 'bus.dart';
import 'user_summary.dart';

class Excursion {
  const Excursion({
    required this.id,
    required this.title,
    required this.description,
    this.direction = 'west',
    required this.date,
    required this.time,
    required this.dateTime,
    required this.price,
    this.actualAmount,
    required this.maxSeats,
    int? baseMaxSeats,
    this.slotMaxSeats,
    required this.bookedSeatsCount,
    required this.availableSeatsCount,
    required this.assignedStaff,
    required this.busAssignments,
    required this.busSeats,
    required this.tariffs,
    this.staffPrices = const [],
    this.isUnscheduled = false,
    this.unscheduledDateId,
    this.isDeleted = false,
    this.isCancelled = false,
  }) : baseMaxSeats = baseMaxSeats ?? maxSeats;

  final int id;
  final String title;
  final String description;
  final String direction;
  final DateTime date;
  final String time;
  final DateTime dateTime;
  final double? price;
  final double? actualAmount;
  final int maxSeats;
  final int baseMaxSeats;
  final int? slotMaxSeats;
  final int bookedSeatsCount;
  final int availableSeatsCount;
  final List<ExcursionStaff> assignedStaff;
  final List<ExcursionBusAssignment> busAssignments;
  final List<BusSeat> busSeats;
  final Map<String, ExcursionTariff> tariffs;
  final List<StaffPrice> staffPrices;
  final bool isUnscheduled;
  final int? unscheduledDateId; // ID внеплановой даты для удаления
  final bool isDeleted; // Помечена ли как удаленная
  final bool isCancelled; // Отменена ли экскурсия

  bool get isPast => dateTime.isBefore(DateTime.now());

  factory Excursion.fromJson(Map<String, dynamic> json) {
    final seatsJson = json['bus_seats'] as List<dynamic>?;
    final staffJson = json['assigned_staff'] as List<dynamic>?;
    final busAssignmentsJson = json['bus_assignments'] as List<dynamic>?;
    final pricesJson = json['prices'] as List<dynamic>?;

    // date_time теперь может быть null (экскурсии стали шаблонами)
    final dateTimeStr = json['date_time'] as String?;
    DateTime? dateTime;
    DateTime? date;
    if (dateTimeStr != null && dateTimeStr.isNotEmpty) {
      dateTime = DateTime.parse(dateTimeStr);
      // Создаем date в том же часовом поясе, что и dateTime
      date = DateTime(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          dateTime.microsecond);
    } else {
      // Если date_time null, используем текущую дату как fallback
      dateTime = DateTime.now();
      date = DateTime.now();
    }

    return Excursion(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      direction: json['direction'] as String? ?? 'west',
      date: date,
      time: json['time'] as String? ?? '',
      dateTime: dateTime,
      price: json['price'] != null
          ? double.tryParse(json['price'].toString())
          : null,
      actualAmount: json['actual_amount'] != null
          ? double.tryParse(json['actual_amount'].toString())
          : null,
      maxSeats: (json['slot_max_seats'] as num?)?.toInt() ??
          (json['max_seats'] as num?)?.toInt() ??
          0,
      baseMaxSeats: (json['max_seats'] as num?)?.toInt() ?? 0,
      slotMaxSeats: (json['slot_max_seats'] as num?)?.toInt(),
      bookedSeatsCount: json['booked_seats_count'] as int? ?? 0,
      availableSeatsCount: json['available_seats_count'] as int? ?? 0,
      assignedStaff: staffJson == null
          ? const []
          : staffJson
              .map((item) =>
                  ExcursionStaff.fromJson(item as Map<String, dynamic>))
              .toList(),
      busAssignments: busAssignmentsJson == null
          ? const []
          : busAssignmentsJson
              .map((item) => ExcursionBusAssignment.fromJson(
                    item as Map<String, dynamic>,
                  ))
              .toList(),
      busSeats: seatsJson == null
          ? const []
          : seatsJson
              .map((seat) => BusSeat.fromJson(seat as Map<String, dynamic>))
              .toList(),
      tariffs: _parseTariffs(
        pricesJson,
        json['price'] != null
            ? double.tryParse(json['price'].toString()) ?? 0.0
            : 0.0,
      ),
      staffPrices: _parseStaffPrices(json['staff_prices'] as List<dynamic>?),
      isUnscheduled: json['is_unscheduled'] as bool? ?? false,
      unscheduledDateId: json['unscheduled_date_id'] as int?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      isCancelled: json['is_cancelled'] as bool? ?? false,
    );
  }

  static List<StaffPrice> _parseStaffPrices(List<dynamic>? staffPricesJson) {
    if (staffPricesJson == null || staffPricesJson.isEmpty) {
      return [];
    }
    return staffPricesJson
        .map((item) => StaffPrice.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Map<String, ExcursionTariff> _parseTariffs(
    List<dynamic>? pricesJson,
    double defaultPrice,
  ) {
    final defaultTariff = ExcursionTariff(
      price: defaultPrice,
      sellerCommissionPercent: 10,
      partnerCommissionPercent: 10,
      priceWithoutEntry: defaultPrice,
      priceWithEntry: defaultPrice,
    );

    if (pricesJson == null || pricesJson.isEmpty) {
      return {
        'adult': defaultTariff,
        'child': defaultTariff,
        'senior': defaultTariff,
        'disabled': defaultTariff,
        'special': defaultTariff,
      };
    }

    final map = <String, ExcursionTariff>{
      'adult': defaultTariff,
      'child': defaultTariff,
      'senior': defaultTariff,
      'disabled': defaultTariff,
      'special': defaultTariff,
    };

    for (final item in pricesJson) {
      final json = item as Map<String, dynamic>?;
      if (json == null) {
        continue;
      }
      final type = json['passenger_type'] as String?;
      if (type == null || type.isEmpty) {
        continue;
      }

      final priceValue =
          double.tryParse(json['price']?.toString() ?? '') ?? defaultPrice;
      final seller = double.tryParse(
            json['seller_commission_percent']?.toString() ?? '',
          ) ??
          10;
      final partner = double.tryParse(
            json['partner_commission_percent']?.toString() ?? '',
          ) ??
          10;
      final priceWithoutEntry = json['price_without_entry'] != null
          ? double.tryParse(json['price_without_entry']?.toString() ?? '')
          : null;
      final priceWithEntry = json['price_with_entry'] != null
          ? double.tryParse(json['price_with_entry']?.toString() ?? '')
          : null;

      map[type] = ExcursionTariff(
        price: priceValue,
        sellerCommissionPercent: seller,
        partnerCommissionPercent: partner,
        priceWithoutEntry: priceWithoutEntry ?? priceValue,
        priceWithEntry: priceWithEntry ?? priceValue,
      );
    }

    return map;
  }

  double priceFor(String passengerType) {
    return tariffs[passengerType]?.price ?? price ?? 0.0;
  }
}

class ExcursionBusAssignment {
  const ExcursionBusAssignment({
    required this.id,
    required this.busId,
    required this.driverId,
    required this.excursionDate,
    required this.time,
    required this.seatFrom,
    required this.seatTo,
    required this.allocatedSeats,
    this.bus,
    this.driver,
  });

  final int id;
  final int busId;
  final int driverId;
  final String? excursionDate;
  final String? time;
  final int seatFrom;
  final int seatTo;
  final int allocatedSeats;
  final Bus? bus;
  final UserSummary? driver;

  factory ExcursionBusAssignment.fromJson(Map<String, dynamic> json) {
    return ExcursionBusAssignment(
      id: (json['id'] as num?)?.toInt() ?? 0,
      busId: (json['bus_id'] as num?)?.toInt() ?? 0,
      driverId: (json['driver_id'] as num?)?.toInt() ?? 0,
      excursionDate: json['excursion_date'] as String?,
      time: json['time'] as String?,
      seatFrom: (json['seat_from'] as num?)?.toInt() ?? 0,
      seatTo: (json['seat_to'] as num?)?.toInt() ?? 0,
      allocatedSeats: (json['allocated_seats'] as num?)?.toInt() ?? 0,
      bus: json['bus'] is Map<String, dynamic>
          ? Bus.fromJson(json['bus'] as Map<String, dynamic>)
          : null,
      driver: json['driver'] is Map<String, dynamic>
          ? UserSummary.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
    );
  }
}

class ExcursionTariff {
  const ExcursionTariff({
    required this.price,
    required this.sellerCommissionPercent,
    required this.partnerCommissionPercent,
    this.priceWithoutEntry,
    this.priceWithEntry,
  });

  final double price;
  final double sellerCommissionPercent;
  final double partnerCommissionPercent;
  final double? priceWithoutEntry;
  final double? priceWithEntry;
}

class ExcursionStaff {
  const ExcursionStaff({
    required this.id,
    required this.name,
    required this.email,
    required this.roleInExcursion,
    this.excursionDate,
    this.time,
    this.manualAmount,
    this.isAutoGuideFromDriver = false,
  });

  final int id;
  final String name;
  final String email;
  final String roleInExcursion; // driver | guide
  final String? excursionDate; // YYYY-MM-DD или null (на все даты)
  final String? time; // HH:MM или null (на все времена)
  final double? manualAmount;
  final bool isAutoGuideFromDriver;

  factory ExcursionStaff.fromJson(Map<String, dynamic> json) {
    return ExcursionStaff(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      roleInExcursion: json['role_in_excursion'] as String? ?? '',
      excursionDate: json['excursion_date'] as String?,
      time: json['time'] as String?,
      manualAmount: json['manual_amount'] != null
          ? double.tryParse(json['manual_amount'].toString())
          : null,
      isAutoGuideFromDriver: false,
    );
  }

  ExcursionStaff asAutoGuideFromDriver() {
    return ExcursionStaff(
      id: id,
      name: name,
      email: email,
      roleInExcursion: 'guide',
      excursionDate: excursionDate,
      time: time,
      manualAmount: manualAmount,
      isAutoGuideFromDriver: true,
    );
  }
}

class StaffPrice {
  const StaffPrice({
    required this.staffType,
    required this.minPassengers,
    this.maxPassengers,
    required this.price,
  });

  final String staffType; // driver | guide
  final int minPassengers;
  final int? maxPassengers;
  final double price;

  factory StaffPrice.fromJson(Map<String, dynamic> json) {
    return StaffPrice(
      staffType: json['staff_type'] as String,
      minPassengers: (json['min_passengers'] as num?)?.toInt() ?? 0,
      maxPassengers: (json['max_passengers'] as num?)?.toInt(),
      price: double.tryParse(json['price'].toString()) ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'staff_type': staffType,
      'min_passengers': minPassengers,
      'max_passengers': maxPassengers,
      'price': price,
    };
  }
}
