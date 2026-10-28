import 'package:flutter_test/flutter_test.dart';
import 'package:booking_app/src/data/models/excursion.dart';
import 'package:booking_app/src/data/models/booking.dart';
import 'package:booking_app/src/data/models/profit.dart';
import 'package:booking_app/src/data/models/wallet.dart';
import 'package:booking_app/src/data/models/bus_seat.dart';

void main() {
  group('Null Safety Tests', () {
    test('Excursion.fromJson handles null price correctly', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'description': 'Test Description',
        'date_time': '2025-12-01T10:00:00Z',
        'date': '2025-12-01',
        'time': '10:00',
        'price': null,
        'max_seats': 50,
        'booked_seats_count': 0,
        'available_seats_count': 50,
        'assigned_staff': [],
        'bus_seats': [],
        'prices': [],
      };

      expect(() => Excursion.fromJson(json), returnsNormally);
      final excursion = Excursion.fromJson(json);
      expect(excursion.price, isNull);
      expect(excursion.priceFor('adult'), 0.0);
    });

    test('Excursion.fromJson handles empty string price correctly', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'description': 'Test Description',
        'date_time': '2025-12-01T10:00:00Z',
        'date': '2025-12-01',
        'time': '10:00',
        'price': '',
        'max_seats': 50,
        'booked_seats_count': 0,
        'available_seats_count': 50,
        'assigned_staff': [],
        'bus_seats': [],
        'prices': [],
      };

      expect(() => Excursion.fromJson(json), returnsNormally);
      final excursion = Excursion.fromJson(json);
      expect(excursion.price, isNull);
    });

    test('BookingExcursion.fromJson handles null price correctly', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'date': DateTime.now(),
        'time': '10:00',
        'date_time': '2025-12-01T10:00:00Z',
        'price': null,
      };

      expect(() => BookingExcursion.fromJson(json), returnsNormally);
      final bookingExcursion = BookingExcursion.fromJson(json);
      expect(bookingExcursion.price, 0.0);
    });

    test('BookingItem.fromJson handles null booked_at correctly', () {
      final json = {
        'id': 1,
        'excursion': {
          'id': 1,
          'title': 'Test',
          'date': DateTime.now(),
          'time': '10:00',
          'date_time': '2025-12-01T10:00:00Z',
          'price': 1000,
        },
        'bus_seat': {
          'id': 1,
          'seat_number': 1,
        },
        'price': 1000,
        'customer_name': 'Test',
        'customer_phone': '123',
        'passenger_type': 'adult',
        'booked_at': null,
        'created_at': null,
      };

      expect(() => BookingItem.fromJson(json), returnsNormally);
      final booking = BookingItem.fromJson(json);
      expect(booking.bookedAt, isNotNull);
    });

    test('ProfitItem.fromJson handles null booked_at correctly', () {
      final json = {
        'booking_id': 1,
        'excursion': {
          'id': 1,
          'title': 'Test',
          'date_time': '2025-12-01T10:00:00Z',
        },
        'passenger_type': 'adult',
        'price': 1000,
        'commission_percent': 10,
        'commission_amount': 100,
        'booked_at': null,
      };

      expect(() => ProfitItem.fromJson(json), returnsNormally);
      final profitItem = ProfitItem.fromJson(json);
      expect(profitItem.bookedAt, isNotNull);
    });

    test('ProfitExcursion.fromJson handles null date_time correctly', () {
      final json = {
        'id': 1,
        'title': 'Test',
        'date_time': null,
      };

      expect(() => ProfitExcursion.fromJson(json), returnsNormally);
      final profitExcursion = ProfitExcursion.fromJson(json);
      expect(profitExcursion.dateTime, isNotNull);
    });

    test('WalletTransactionItem.fromJson handles null created_at correctly',
        () {
      final json = {
        'id': 1,
        'amount': 1000,
        'description': 'Test',
        'booking': null,
        'created_at': null,
      };

      expect(() => WalletTransactionItem.fromJson(json), returnsNormally);
      final transaction = WalletTransactionItem.fromJson(json);
      expect(transaction.createdAt, isNotNull);
    });

    test('BusSeat.fromJson handles null booked_at correctly', () {
      final json = {
        'id': 1,
        'seat_number': 1,
        'status': 'available',
        'booked_by': null,
        'booked_at': null,
      };

      expect(() => BusSeat.fromJson(json), returnsNormally);
      final seat = BusSeat.fromJson(json);
      expect(seat.bookedAt, isNull);
    });

    test('Excursion.fromJson handles null date_time gracefully', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'description': 'Test Description',
        'date_time': null,
        'date': '2025-12-01',
        'time': '10:00',
        'price': null,
        'max_seats': 50,
        'booked_seats_count': 0,
        'available_seats_count': 50,
        'assigned_staff': [],
        'bus_seats': [],
        'prices': [],
      };

      // date_time обязателен, поэтому ожидаем ошибку
      expect(() => Excursion.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('BookingExcursion.fromJson handles null date_time gracefully', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'date': DateTime.now(),
        'time': '10:00',
        'date_time': null,
        'price': null,
      };

      // date_time обязателен, поэтому ожидаем ошибку
      expect(() => BookingExcursion.fromJson(json), throwsA(isA<TypeError>()));
    });

    test('Excursion.fromJson handles prices with null values correctly', () {
      final json = {
        'id': 1,
        'title': 'Test Excursion',
        'description': 'Test Description',
        'date_time': '2025-12-01T10:00:00Z',
        'date': '2025-12-01',
        'time': '10:00',
        'price': null,
        'max_seats': 50,
        'booked_seats_count': 0,
        'available_seats_count': 50,
        'assigned_staff': [],
        'bus_seats': [],
        'prices': [
          {
            'passenger_type': 'adult',
            'price': null,
            'price_without_entry': null,
            'price_with_entry': null,
            'seller_commission_percent': null,
            'partner_commission_percent': null,
          },
        ],
      };

      expect(() => Excursion.fromJson(json), returnsNormally);
      final excursion = Excursion.fromJson(json);
      expect(excursion.tariffs['adult'], isNotNull);
      expect(excursion.tariffs['adult']!.price, 0.0);
    });
  });
}








