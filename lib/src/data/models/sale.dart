class Sale {
  const Sale({
    required this.id,
    required this.excursion,
    required this.customerName,
    required this.customerPhone,
    required this.passengerType,
    required this.price,
    this.stop,
    this.bookedAt,
    this.settlement,
  });

  final int id;
  final SaleExcursion excursion;
  final String customerName;
  final String customerPhone;
  final String passengerType;
  final double price;
  final StopInfo? stop;
  final DateTime? bookedAt;
  final SaleSettlement? settlement;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: (json['id'] as num).toInt(),
      excursion: SaleExcursion.fromJson(json['excursion'] as Map<String, dynamic>),
      customerName: json['customer_name'] as String? ?? '',
      customerPhone: json['customer_phone'] as String? ?? '',
      passengerType: json['passenger_type'] as String? ?? 'adult',
      price: (json['price'] as num).toDouble(),
      stop: json['stop'] != null
          ? StopInfo.fromJson(json['stop'] as Map<String, dynamic>)
          : null,
      bookedAt: json['booked_at'] != null
          ? DateTime.parse(json['booked_at'] as String)
          : null,
      settlement: json['settlement'] != null
          ? SaleSettlement.fromJson(json['settlement'] as Map<String, dynamic>)
          : null,
    );
  }
}

class SaleSettlement {
  const SaleSettlement({
    required this.id,
    required this.settlementDate,
    required this.totalAmount,
  });

  final int id;
  final DateTime settlementDate;
  final double totalAmount;

  factory SaleSettlement.fromJson(Map<String, dynamic> json) {
    return SaleSettlement(
      id: (json['id'] as num).toInt(),
      settlementDate: DateTime.parse(json['settlement_date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
    );
  }
}

class SaleExcursion {
  const SaleExcursion({
    required this.id,
    required this.title,
    this.dateTime,
  });

  final int id;
  final String title;
  final DateTime? dateTime;

  factory SaleExcursion.fromJson(Map<String, dynamic> json) {
    return SaleExcursion(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String? ?? '',
      dateTime: json['date_time'] != null
          ? DateTime.parse(json['date_time'] as String)
          : null,
    );
  }
}

class StopInfo {
  const StopInfo({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory StopInfo.fromJson(Map<String, dynamic> json) {
    return StopInfo(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
    );
  }
}
