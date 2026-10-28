import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import 'models/booking.dart';
import 'models/excursion.dart';
import 'models/stop.dart';
import 'models/user_role_info.dart';
import 'models/user_summary.dart';
import 'models/wallet.dart';
import 'models/profit.dart';
import 'models/schedule_template.dart';
import 'repositories/auth_repository.dart';
import 'repositories/excursions_repository.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/assignments_repository.dart';
import 'repositories/stops_repository.dart';
import 'repositories/users_repository.dart';
import 'repositories/wallet_repository.dart';
import 'repositories/schedule_repository.dart';
import 'repositories/settlements_repository.dart';
import 'repositories/buses_repository.dart';
import 'models/bus.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.instance;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

final excursionsRepositoryProvider = Provider<ExcursionsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ExcursionsRepository(client);
});

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return BookingsRepository(client);
});

final usersRepositoryProvider = Provider<UsersRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return UsersRepository(client);
});

final stopsRepositoryProvider = Provider<StopsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return StopsRepository(client);
});

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return WalletRepository(client);
});

final assignmentsRepositoryProvider = Provider<AssignmentsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return AssignmentsRepository(client);
});

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return ScheduleRepository(client);
});

final settlementsRepositoryProvider = Provider<SettlementsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return SettlementsRepository(client);
});

final busesRepositoryProvider = Provider<BusesRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return BusesRepository(client);
});

final busesFutureProvider = FutureProvider<List<Bus>>((ref) async {
  final repository = ref.watch(busesRepositoryProvider);
  return repository.fetchBuses();
});

final excursionsFutureProvider = FutureProvider<List<Excursion>>((ref) {
  final repository = ref.watch(excursionsRepositoryProvider);
  return repository.fetchExcursions();
});

/// Экскурсии для персонала — использует API /api/excursions
/// который уже фильтрует по назначениям с учётом даты
final staffExcursionsFutureProvider = FutureProvider.family<List<Excursion>, int>((ref, userId) async {
  final repository = ref.watch(excursionsRepositoryProvider);
  return repository.fetchExcursions();
});

final bookingsFutureProvider = FutureProvider<List<BookingGroup>>((ref) {
  final repository = ref.watch(bookingsRepositoryProvider);
  return repository.fetchBookings();
});

final stopsFutureProvider = FutureProvider<List<Stop>>((ref) {
  final repository = ref.watch(stopsRepositoryProvider);
  return repository.fetchStops();
});

final allUsersFutureProvider = FutureProvider<List<UserSummary>>((ref) {
  final repository = ref.watch(usersRepositoryProvider);
  return repository.fetchUsers();
});

final userRolesFutureProvider = FutureProvider<List<UserRoleInfo>>((ref) {
  final repository = ref.watch(usersRepositoryProvider);
  return repository.fetchRoles();
});

final userWalletFutureProvider =
    FutureProvider.family<WalletInfo, int>((ref, userId) {
  final repository = ref.watch(walletRepositoryProvider);
  return repository.fetchWallet(userId);
});

final userSalesFutureProvider =
    FutureProvider.family<SalesInfo, int>((ref, userId) {
  final repository = ref.watch(walletRepositoryProvider);
  return repository.fetchSales(userId);
});

final userProfitFutureProvider =
    FutureProvider.family<ProfitInfo, int>((ref, userId) {
  final repository = ref.watch(walletRepositoryProvider);
  return repository.fetchProfit(userId);
});

final scheduleFutureProvider = FutureProvider<List<ScheduleTemplate>>((ref) {
  final repository = ref.watch(scheduleRepositoryProvider);
  return repository.fetchSchedule();
});

final staffProfitFutureProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, userId) {
  final repository = ref.watch(walletRepositoryProvider);
  return repository.fetchStaffProfit(userId);
});
