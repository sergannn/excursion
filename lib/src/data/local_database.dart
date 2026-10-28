import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import '../core/utils.dart';
import 'models.dart';

class LocalDatabase {
  LocalDatabase._();

  static final LocalDatabase instance = LocalDatabase._();

  static const _usersBoxName = 'users_box';
  static const _excursionsBoxName = 'excursions_box';
  static const _bookingsBoxName = 'bookings_box';
  static const _walletBoxName = 'wallet_box';
  static const _priceRulesBoxName = 'price_rules_box';
  static const _stopsBoxName = 'stops_box';

  Box<UserProfile>? _usersBox;
  Box<Excursion>? _excursionsBox;
  Box<Booking>? _bookingsBox;
  Box<WalletTransaction>? _walletBox;
  Box<PriceRule>? _priceRulesBox;
  Box<StopPoint>? _stopsBox;

  Box<UserProfile> get usersBox => _usersBox!;
  Box<Excursion> get excursionsBox => _excursionsBox!;
  Box<Booking> get bookingsBox => _bookingsBox!;
  Box<WalletTransaction> get walletBox => _walletBox!;
  Box<PriceRule> get priceRulesBox => _priceRulesBox!;
  Box<StopPoint> get stopsBox => _stopsBox!;

  Future<void> bootstrap() async {
    await Hive.initFlutter();
    _registerAdapters();
    _usersBox = await Hive.openBox<UserProfile>(_usersBoxName);
    _excursionsBox = await Hive.openBox<Excursion>(_excursionsBoxName);
    _bookingsBox = await Hive.openBox<Booking>(_bookingsBoxName);
    _walletBox = await Hive.openBox<WalletTransaction>(_walletBoxName);
    _priceRulesBox = await Hive.openBox<PriceRule>(_priceRulesBoxName);
    _stopsBox = await Hive.openBox<StopPoint>(_stopsBoxName);

    if (_usersBox!.isEmpty || _excursionsBox!.isEmpty) {
      await _seed();
    }
  }

  void _registerAdapters() {
    if (Hive.isAdapterRegistered(1)) {
      return;
    }
    Hive
      ..registerAdapter(UserRoleAdapter())
      ..registerAdapter(PassengerTypeAdapter())
      ..registerAdapter(BookingStatusAdapter())
      ..registerAdapter(PriceTierAdapter())
      ..registerAdapter(UserProfileAdapter())
      ..registerAdapter(ExcursionAdapter())
      ..registerAdapter(BookingAdapter())
      ..registerAdapter(WalletTransactionAdapter())
      ..registerAdapter(PriceRuleAdapter())
      ..registerAdapter(StopPointAdapter());
  }

  Future<void> _seed() async {
    final stops = await _loadStops();
    for (final stop in stops) {
      await stopsBox.put(stop.id, stop);
    }

    final users = _defaultUsers();
    for (final user in users) {
      await usersBox.put(user.id, user);
    }

    final excursions = await _loadExcursions(stops);
    for (final excursion in excursions) {
      await excursionsBox.put(excursion.id, excursion);
    }

    final rules = _defaultPriceRules(excursions);
    for (final rule in rules) {
      await priceRulesBox.put(rule.id, rule);
    }
  }

  Future<List<StopPoint>> _loadStops() async {
    try {
      final raw = await rootBundle.loadString('assets/data/stops.json');
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isNotEmpty) {
        return list
            .map((item) => StopPoint(
                id: item['id'] as String, name: item['name'] as String))
            .toList();
      }
    } catch (_) {}
    return _generateDefaultStops();
  }

  Future<List<Excursion>> _loadExcursions(List<StopPoint> stops) async {
    try {
      final raw = await rootBundle.loadString('assets/data/schedule.json');
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isNotEmpty) {
        return list.map((item) {
          final dateTime = DateTime.parse(item['datetime'] as String);
          final stopCodes = (item['stops'] as List<dynamic>).cast<String>();
          final validStops =
              stopCodes.where((id) => stops.any((s) => s.id == id)).toList();
          return Excursion(
            id: item['id'] as String,
            title: item['title'] as String,
            dateTime: dateTime,
            stopIds: validStops,
            driverIds: <String>[],
            guideIds: <String>[],
            guideRequired: item['guideRequired'] as bool? ?? true,
            baseCapacity: item['baseCapacity'] as int? ?? 21,
          );
        }).toList();
      }
    } catch (_) {}
    return _generateDefaultExcursions(stops);
  }

  List<StopPoint> _generateDefaultStops() {
    const names = [
      'Морской порт',
      'Центральная площадь',
      'Исторический музей',
      'Парк Победы',
      'Крепость Петра',
      'Видовая площадка',
    ];
    return List.generate(
      names.length,
      (index) => StopPoint(
        id: 'stop-${index + 1}',
        name: names[index],
      ),
    );
  }

  List<Excursion> _generateDefaultExcursions(List<StopPoint> stops) {
    if (stops.isEmpty) {
      return [];
    }

    final rand = Random();
    final now = DateTime.now();
    final tours = <Excursion>[];
    const titles = [
      'Город над Невской волной',
      'Тайны старого квартала',
      'Река и мосты',
      'Северное сияние истории',
      'Прогулка по крышам',
      'Золотые купола',
    ];
    final timeSlots = [
      const Duration(hours: 9),
      const Duration(hours: 13, minutes: 30),
      const Duration(hours: 18),
    ];

    for (var dayOffset = 0; dayOffset < 10; dayOffset++) {
      final dateBase = now.add(Duration(days: dayOffset));
      final toursPerDay =
          min(timeSlots.length, 2 + rand.nextInt(timeSlots.length));
      final slots = List<Duration>.from(timeSlots)..shuffle(rand);
      for (var i = 0; i < toursPerDay; i++) {
        final slot = slots[i];
        final date = DateTime(
          dateBase.year,
          dateBase.month,
          dateBase.day,
        ).add(slot);
        final title = titles[rand.nextInt(titles.length)];
        final shuffledStops = List<StopPoint>.from(stops)..shuffle(rand);
        final stopCount = shuffledStops.length >= 3
            ? min(5, shuffledStops.length)
            : shuffledStops.length;
        final stopIds =
            shuffledStops.take(max(1, stopCount)).map((s) => s.id).toList();
        tours.add(
          Excursion(
            id: generateId(prefix: 'exc'),
            title:
                '$title (${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')})',
            dateTime: date,
            stopIds: stopIds,
            driverIds: <String>[],
            guideIds: <String>[],
            guideRequired: rand.nextBool(),
            baseCapacity: 21,
          ),
        );
      }
    }

    tours.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return tours;
  }

  List<UserProfile> _defaultUsers() {
    return [
      UserProfile(
        id: 'admin-1',
        displayName: 'Администратор',
        shortName: 'Админ',
        role: UserRole.admin,
        login: 'admin',
        password: '1234',
      ),
      UserProfile(
        id: 'seller-1',
        displayName: 'Светлана П. (продавец)',
        shortName: 'Светлана П.',
        role: UserRole.seller,
        login: 'svetlana',
        password: '1234',
      ),
      UserProfile(
        id: 'seller-2',
        displayName: 'Иван К. (партнёр)',
        shortName: 'Иван К.',
        role: UserRole.partnerSeller,
        login: 'ivan',
        password: '1234',
      ),
      UserProfile(
        id: 'driver-1',
        displayName: 'Алексей Д. (водитель)',
        shortName: 'Алексей Д.',
        role: UserRole.driver,
        login: 'alexey',
        password: '1234',
      ),
      UserProfile(
        id: 'guide-1',
        displayName: 'Мария Г. (гид)',
        shortName: 'Мария Г.',
        role: UserRole.guide,
        login: 'maria',
        password: '1234',
      ),
    ];
  }

  List<PriceRule> _defaultPriceRules(List<Excursion> excursions) {
    final rules = <PriceRule>[];
    for (final excursion in excursions) {
      for (final tier in PriceTier.values) {
        rules.add(
          PriceRule(
            id: generateId(prefix: 'prc'),
            excursionId: excursion.id,
            tier: tier,
            sellerPayout: _sellerPayoutForTier(tier),
            driverPayout: _driverPayoutForTier(tier),
            guidePayout: _guidePayoutForTier(tier),
          ),
        );
      }
    }
    return rules;
  }

  double _sellerPayoutForTier(PriceTier tier) {
    switch (tier) {
      case PriceTier.standard:
        return 1200;
      case PriceTier.upTo15:
        return 1000;
      case PriceTier.upTo10:
        return 800;
      case PriceTier.upTo5:
        return 600;
    }
  }

  double _driverPayoutForTier(PriceTier tier) {
    switch (tier) {
      case PriceTier.standard:
        return 5000;
      case PriceTier.upTo15:
        return 4200;
      case PriceTier.upTo10:
        return 3500;
      case PriceTier.upTo5:
        return 2500;
    }
  }

  double _guidePayoutForTier(PriceTier tier) {
    switch (tier) {
      case PriceTier.standard:
        return 3000;
      case PriceTier.upTo15:
        return 2500;
      case PriceTier.upTo10:
        return 2000;
      case PriceTier.upTo5:
        return 1500;
    }
  }
}
