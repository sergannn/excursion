import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:booking_app/src/data/models/booking.dart';
import 'package:booking_app/src/data/models/bus_seat.dart';
import 'package:booking_app/src/data/models/excursion.dart';
import 'package:booking_app/src/data/models/stop.dart';
import 'package:booking_app/src/data/models/user.dart';
import 'package:booking_app/src/data/models/user_summary.dart';
import 'package:booking_app/src/data/models/wallet.dart';
import 'package:booking_app/src/data/models/profit.dart';
import 'package:booking_app/src/data/providers.dart';
import 'package:booking_app/src/features/admin/admin_home.dart';
import 'package:booking_app/src/features/seller/seller_home.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sellerUser = User(
    id: 1,
    name: 'Анна Продавец',
    email: 'anna@excursion.ru',
    role: 'seller',
    roleId: 2,
    isSuperUser: false,
  );

  final adminUser = User(
    id: 10,
    name: 'Админ',
    email: 'admin@excursion.ru',
    role: 'admin',
    roleId: 1,
    isSuperUser: true,
  );

  final sampleStops = [
    const Stop(id: 1, name: 'Центральная', order: 1),
    const Stop(id: 2, name: 'Парк', order: 2),
  ];

  final sampleExcursions = [
    Excursion(
      id: 101,
      title: 'Суперкруиз',
      description: 'Ай-Петри, Черепашье озеро, прогулка по Ялте',
      date: DateTime(2025, 11, 5),
      time: '08:30',
      dateTime: DateTime(2025, 11, 5, 8, 30),
      price: 1500,
      maxSeats: 20,
      bookedSeatsCount: 4,
      availableSeatsCount: 16,
      assignedStaff: const [
        ExcursionStaff(
          id: 301,
          name: 'Иван Водитель',
          email: 'ivan@excursion.ru',
          roleInExcursion: 'driver',
        ),
        ExcursionStaff(
          id: 302,
          name: 'Мария Гид',
          email: 'maria@excursion.ru',
          roleInExcursion: 'guide',
        ),
      ],
      busSeats: List.generate(10, (index) {
        final seatNumber = index + 1;
        final isBooked = seatNumber <= 4;
        return BusSeat(
          id: seatNumber,
          seatNumber: seatNumber,
          status: isBooked ? 'booked' : 'available',
          bookedBy: isBooked ? sellerUser.id : null,
          bookedAt: isBooked ? DateTime.now().subtract(const Duration(days: 1)) : null,
        );
      }),
      tariffs: const {
        'adult': ExcursionTariff(
          price: 1500.0,
          sellerCommissionPercent: 10,
          partnerCommissionPercent: 12,
        ),
        'child': ExcursionTariff(
          price: 1200.0,
          sellerCommissionPercent: 8,
          partnerCommissionPercent: 10,
        ),
        'senior': ExcursionTariff(
          price: 1200.0,
          sellerCommissionPercent: 8,
          partnerCommissionPercent: 10,
        ),
        'disabled': ExcursionTariff(
          price: 1100.0,
          sellerCommissionPercent: 7,
          partnerCommissionPercent: 9,
        ),
      },
    ),
  ];

  final bookingExcursion = BookingExcursion(
    id: 101,
    title: 'Суперкруиз',
    date: DateTime(2025, 11, 1, 8, 30),
    time: '08:30',
    dateTime: DateTime(2025, 11, 1, 8, 30),
    price: 1500,
  );

  final sampleBookingGroups = [
    BookingGroup(
      excursion: bookingExcursion,
      bookings: [
        BookingItem(
          id: 501,
          excursion: bookingExcursion,
          seat: const BookingSeat(id: 1, seatNumber: 1),
          price: 1500,
          customerName: 'Пётр Клиент',
          customerPhone: '+7 999 123-45-67',
          passengerType: PassengerType.adult,
          stop: sampleStops.first,
          bookedAt: DateTime(2025, 10, 25, 10, 0),
        ),
      ],
    ),
  ];

  final walletInfo = WalletInfo(
    user: WalletUser(id: sellerUser.id, name: sellerUser.name, email: sellerUser.email),
    balance: 4500,
    transactions: const [],
  );

  final salesInfo = SalesInfo(
    user: WalletUser(id: sellerUser.id, name: sellerUser.name, email: sellerUser.email),
    totalSales: 4500,
    bookings: sampleBookingGroups.first.bookings,
  );

  final profitInfo = ProfitInfo(
    user: WalletUser(id: sellerUser.id, name: sellerUser.name, email: sellerUser.email),
    totalProfit: 450,
    breakdown: [
      ProfitItem(
        bookingId: 501,
        excursion: ProfitExcursion(
          id: bookingExcursion.id,
          title: bookingExcursion.title,
          dateTime: bookingExcursion.dateTime,
        ),
        passengerType: PassengerType.adult,
        price: 1500,
        commissionPercent: 10,
        commissionAmount: 150,
        bookedAt: DateTime(2025, 10, 25, 10, 0),
      ),
    ],
    totalsByType: {
      PassengerType.adult: const ProfitTotals(sales: 1500, commission: 150),
    },
    isPartner: false,
  );

  final adminUsers = [
    const UserSummary(
      id: 1,
      name: 'Анна Продавец',
      email: 'anna@excursion.ru',
      roleName: 'Продавец',
      roleId: 2,
      balance: 4500,
    ),
    const UserSummary(
      id: 2,
      name: 'Борис Гид',
      email: 'boris@excursion.ru',
      roleName: 'Гид',
      roleId: 3,
      balance: 0,
    ),
  ];

  Future<void> pumpForGolden(
    WidgetTester tester,
    Widget child,
    List<Override> overrides,
    String goldenPath,
  ) async {
    tester.binding.platformDispatcher.implicitView!.physicalSize = const Size(1024, 768);
    tester.binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.binding.platformDispatcher.implicitView!.physicalSize = const Size(800, 600);
      tester.binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: child,
        ),
      ),
    );

    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$goldenPath'),
    );
  }

  testWidgets('Seller home golden', (tester) async {
    await pumpForGolden(
      tester,
      SellerHomePage(user: sellerUser),
      [
        excursionsFutureProvider.overrideWith((ref) async => sampleExcursions),
        bookingsFutureProvider.overrideWith((ref) async => sampleBookingGroups),
        stopsFutureProvider.overrideWith((ref) async => sampleStops),
        userWalletFutureProvider.overrideWith((ref, userId) async => walletInfo),
        userSalesFutureProvider.overrideWith((ref, userId) async => salesInfo),
        userProfitFutureProvider.overrideWith((ref, userId) async => profitInfo),
      ],
      'seller_home.png',
    );
  });

  testWidgets('Admin home golden', (tester) async {
    await pumpForGolden(
      tester,
      AdminHomePage(user: adminUser),
      [
        excursionsFutureProvider.overrideWith((ref) async => sampleExcursions),
        bookingsFutureProvider.overrideWith((ref) async => sampleBookingGroups),
        stopsFutureProvider.overrideWith((ref) async => sampleStops),
        allUsersFutureProvider.overrideWith((ref) async => adminUsers),
        userWalletFutureProvider.overrideWith((ref, userId) async => walletInfo),
        userSalesFutureProvider.overrideWith((ref, userId) async => salesInfo),
        userProfitFutureProvider.overrideWith((ref, userId) async => profitInfo),
      ],
      'admin_home.png',
    );
  });
}
