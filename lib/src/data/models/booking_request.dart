import 'booking.dart';

class BookingRequest {
  BookingRequest({
    this.excursionId,
    this.seatNumbers = const [],
    this.price,
    this.customerName = '',
    this.customerPhone = '',
    this.passengerType = PassengerType.adult,
    this.stopId,
  });

  final int? excursionId;
  final List<int> seatNumbers;
  final double? price;
  final String customerName;
  final String customerPhone;
  final PassengerType passengerType;
  final int? stopId;

  BookingRequest copyWith({
    int? excursionId,
    List<int>? seatNumbers,
    double? price,
    String? customerName,
    String? customerPhone,
    PassengerType? passengerType,
    int? stopId,
  }) {
    return BookingRequest(
      excursionId: excursionId ?? this.excursionId,
      seatNumbers: seatNumbers ?? this.seatNumbers,
      price: price ?? this.price,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      passengerType: passengerType ?? this.passengerType,
      stopId: stopId ?? this.stopId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'excursion_id': excursionId,
      'seat_numbers': seatNumbers,
      'price': price,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'passenger_type': passengerType.apiValue,
      'stop_id': stopId,
    };
  }
}
