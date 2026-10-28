import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/models/excursion.dart';
import '../../data/models/user.dart';
import '../../data/models/booking.dart';
import '../../data/models/bus_seat.dart';
import '../../data/models/bus.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/bookings_repository.dart';
import '../../data/repositories/excursions_repository.dart';
import '../../data/repositories/settlements_repository.dart';
import '../../data/models/seller.dart';
import '../../data/providers.dart';
import '../../core/api/api_helpers.dart';
import '../auth/auth_controller.dart';
import '../seller/widgets/booking_dialog.dart';
import '../common/utils/pdf_downloader.dart';
import '../common/utils/ticket_generator.dart';
import '../common/widgets/cancellation_reason_dialog.dart';
import 'widgets/users_tab.dart';
import 'widgets/assign_staff_sheet.dart';
import 'widgets/prices_tab.dart';
import 'widgets/seat_permissions_tab.dart';
import 'widgets/seat_access_requests_tab.dart';
import 'widgets/buses_tab.dart';
import '../common/settings_screen.dart';
import '../excursions/widgets/excursion_gallery_dialog.dart';
import '../../core/services/internet_connection_service.dart';

enum StaffIndicatorMode { combined, split }

final staffIndicatorModeProvider =
    StateProvider<StaffIndicatorMode>((ref) => StaffIndicatorMode.combined);

// Provider для загрузки экскурсии с деталями бронирований (для схемы рассадки)
final _excursionWithDetailsProvider =
    FutureProvider.autoDispose.family<Excursion?, int>(
  (ref, id) => ref
      .read(excursionsRepositoryProvider)
      .fetchExcursion(id, includeBookingDetails: true),
);

class AdminHomePage extends ConsumerWidget {
  const AdminHomePage({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    // Отслеживаем статус интернета
    final internetStatusAsync = ref.watch(internetStatusProvider);
    final hasInternet = internetStatusAsync.valueOrNull ?? true;

    // Определяем цвет фона AppBar - используем персональный цвет пользователя или цвет темы
    Color? userColor;
    if (user.color != null && user.color!.isNotEmpty) {
      try {
        userColor = Color(
            int.parse(user.color!.replaceFirst('#', ''), radix: 16) +
                0xFF000000);
      } catch (e) {
        // Если не удалось распарсить цвет, используем null
      }
    }

    final appBarColor = userColor ??
        (hasInternet ? Theme.of(context).colorScheme.primary : Colors.red);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: appBarColor,
          foregroundColor: Colors.white, // Белый цвет для всех элементов AppBar
          title: Text(
            isCompact ? 'Администратор' : 'Администратор — ${user.name}',
            style: const TextStyle(
                color: Colors.white), // Явно указываем белый цвет
          ),
          actions: [
            Consumer(
              builder: (context, ref, _) => IconButton(
                color: Colors.white, // Явно указываем белый цвет для иконки
                icon: const Icon(Icons.add),
                tooltip: 'Добавить экскурсию',
                onPressed: () async {
                  final created = await showDialog<Excursion>(
                    context: context,
                    builder: (dialogContext) => const _CreateExcursionDialog(),
                  );
                  if (created == null || !context.mounted) {
                    return;
                  }
                  ref.invalidate(excursionsFutureProvider);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Экскурсия "${created.title}" добавлена'),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
              ),
            ),
            Consumer(
              builder: (context, ref, _) => IconButton(
                color: Colors.white, // Явно указываем белый цвет для иконки
                icon: const Icon(Icons.logout),
                tooltip: 'Выйти',
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            ),
          ],
          bottom: TabBar(
            isScrollable: isCompact,
            tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
            tabs: const [
              Tab(text: 'Бронирование'),
              Tab(text: 'Статистика'),
              Tab(text: 'Сотрудники'),
            ],
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        drawer: _AdminDrawer(user: user),
        body: TabBarView(
          children: [
            _AdminBookingTab(user: user),
            const _AdminStatisticsTab(),
            UsersTab(currentUserId: user.id),
          ],
        ),
      ),
    );
  }
}

class _AdminDrawer extends ConsumerWidget {
  const _AdminDrawer({required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffIndicatorMode = ref.watch(staffIndicatorModeProvider);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Администратор',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet),
            title: const Text('Кошелёк'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, _AdminWalletTab(user: user));
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Расписание'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, const _AdminScheduleTab(), standalone: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.currency_ruble),
            title: const Text('Цены'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, const PricesTab());
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Разрешения на места 1-2'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, const SeatPermissionsTab(), standalone: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.request_quote),
            title: const Text('Запросы доступа'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(
                context,
                const SeatAccessRequestsTab(),
                standalone: true,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.cancel),
            title: const Text('Отмененные экскурсии'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(
                context,
                const _CancelledExcursionsTab(),
                standalone: true,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long),
            title: const Text('Расчетные листы'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, const _SettlementsTab(), standalone: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.directions_bus),
            title: const Text('Автобусы'),
            onTap: () {
              Navigator.of(context).pop();
              _showPage(context, const BusesTab());
            },
          ),
          const Divider(),
          ListTile(
            dense: true,
            title: Text(
              'Настройки',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.people_alt_outlined),
            title: const Text('Отдельные иконки водителей/гидов'),
            subtitle:
                const Text('Показывать два индикатора вместо общей суммы'),
            value: staffIndicatorMode == StaffIndicatorMode.split,
            onChanged: (value) {
              ref.read(staffIndicatorModeProvider.notifier).state = value
                  ? StaffIndicatorMode.split
                  : StaffIndicatorMode.combined;
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Настройки приложения'),
            subtitle: const Text('Интервал проверки интернета и др.'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('О приложении'),
            onTap: () {
              Navigator.of(context).pop();
              showAboutDialog(
                context: context,
                applicationName: 'Система управления экскурсиями',
                applicationVersion: '1.0.0',
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Выход'),
            onTap: () async {
              Navigator.of(context).pop();
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
        ],
      ),
    );
  }

  void _showPage(
    BuildContext context,
    Widget page, {
    bool standalone = false,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => standalone
            ? page
            : Scaffold(
                appBar: AppBar(
                  title: const Text('Администратор'),
                ),
                body: page,
              ),
      ),
    );
  }
}

class _AdminBookingTab extends ConsumerStatefulWidget {
  const _AdminBookingTab({required this.user});

  final User user;

  @override
  ConsumerState<_AdminBookingTab> createState() => _AdminBookingTabState();
}

class _AdminBookingTabState extends ConsumerState<_AdminBookingTab> {
  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            isScrollable: isCompact,
            tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
            tabs: const [
              Tab(text: 'Новое бронирование'),
              Tab(text: 'Мои бронирования'),
              Tab(text: 'Бронирования'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _NewBookingSubTab(user: widget.user),
                _MyBookingsSubTab(user: widget.user),
                _AllBookingsSubTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewBookingSubTab extends ConsumerStatefulWidget {
  const _NewBookingSubTab({required this.user});

  final User user;

  @override
  ConsumerState<_NewBookingSubTab> createState() => _NewBookingSubTabState();
}

class _NewBookingSubTabState extends ConsumerState<_NewBookingSubTab>
    with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  bool _showManagementButtons = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final excursionsAsync = ref.watch(excursionsFutureProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 12,
            spacing: 12,
            children: [
              Text(
                'Новое бронирование',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    icon: Icon(
                      _showManagementButtons
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _showManagementButtons
                          ? 'Скрыть кнопки'
                          : 'Показать кнопки',
                    ),
                    onPressed: () {
                      setState(() {
                        _showManagementButtons = !_showManagementButtons;
                      });
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _selectedDate == null
                          ? 'Выбрать дату'
                          : DateFormat('dd.MM.yyyy').format(_selectedDate!),
                    ),
                    onPressed: () => _selectDate(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_selectedDate != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Сбросить фильтр'),
              onPressed: () {
                setState(() {
                  _selectedDate = null;
                });
              },
            ),
          ),
        Expanded(
          child: excursionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 42),
                    const SizedBox(height: 12),
                    const Text(
                      'Не удалось загрузить экскурсии',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(excursionsFutureProvider),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
            data: (excursions) {
              // Разделяем на текущие/предстоящие и прошедшие.
              // Прошедшими считаем только вчера и раньше:
              // сегодняшние экскурсии остаются в верхнем списке даже после их окончания.
              final now = DateTime.now();
              final todayStart = DateTime(now.year, now.month, now.day);
              final futureExcursions = <Excursion>[];
              final pastExcursions = <Excursion>[];

              for (final excursion in excursions) {
                if (excursion.dateTime.isBefore(todayStart)) {
                  pastExcursions.add(excursion);
                } else {
                  futureExcursions.add(excursion);
                }
              }

              // Фильтруем по выбранной дате
              final filterByDate = (List<Excursion> items) {
                if (_selectedDate == null) return items;
                return items.where((excursion) {
                  final excursionDate = DateTime(
                    excursion.dateTime.year,
                    excursion.dateTime.month,
                    excursion.dateTime.day,
                  );
                  final selectedDateOnly = DateTime(
                    _selectedDate!.year,
                    _selectedDate!.month,
                    _selectedDate!.day,
                  );
                  return excursionDate == selectedDateOnly;
                }).toList();
              };

              final filteredFutureExcursions = filterByDate(futureExcursions);
              final filteredPastExcursions = filterByDate(pastExcursions);

              // Сортируем
              filteredFutureExcursions
                  .sort((a, b) => a.dateTime.compareTo(b.dateTime));
              filteredPastExcursions
                  .sort((a, b) => b.dateTime.compareTo(a.dateTime));

              final dateFormatter = DateFormat('EEEE, dd MMMM yyyy', 'ru_RU');
              final timeFormatter = DateFormat('HH:mm');

              Widget buildExcursionList(
                  List<Excursion> items, String emptyMessage,
                  {bool isPast = false}) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(emptyMessage, textAlign: TextAlign.center),
                  );
                }

                // Группируем по датам
                final groups = <DateTime, List<Excursion>>{};
                for (final excursion in items) {
                  final key = DateTime(
                    excursion.dateTime.year,
                    excursion.dateTime.month,
                    excursion.dateTime.day,
                  );
                  groups.putIfAbsent(key, () => []).add(excursion);
                }
                // Для прошедших экскурсий сортируем по убыванию (самые свежие первыми)
                // Для предстоящих - по возрастанию
                final sortedDates = groups.keys.toList()
                  ..sort(isPast
                      ? (a, b) => b.compareTo(a)
                      : (a, b) => a.compareTo(b));

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedDates.length,
                  itemBuilder: (context, index) {
                    final date = sortedDates[index];
                    final dayItems = groups[date]!;
                    return _ExpandableCard(
                      child: ExpansionTile(
                        title: Text(
                          dateFormatter.format(date),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        subtitle: Text(
                            '${dayItems.length} ${dayItems.length == 1 ? 'экскурсия' : dayItems.length < 5 ? 'экскурсии' : 'экскурсий'}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
                            child: _ExcursionsTableHeader(
                              showActionButtons: _showManagementButtons,
                            ),
                          ),
                          ...dayItems.asMap().entries.map((entry) => Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: _AdminExcursionCard(
                                  excursion: entry.value,
                                  formatter: timeFormatter,
                                  user: widget.user,
                                  index: entry.key,
                                  showActionButtons: _showManagementButtons,
                                ),
                              )),
                        ],
                      ),
                    );
                  },
                );
              }

              return Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    tabs: const [
                      Tab(text: 'Предстоящие'),
                      Tab(text: 'Прошедшие'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        SingleChildScrollView(
                          child: buildExcursionList(
                            filteredFutureExcursions,
                            _selectedDate == null
                                ? 'Нет предстоящих экскурсий'
                                : 'Нет предстоящих экскурсий на выбранную дату',
                            isPast: false,
                          ),
                        ),
                        SingleChildScrollView(
                          child: buildExcursionList(
                            filteredPastExcursions,
                            _selectedDate == null
                                ? 'Нет прошедших экскурсий'
                                : 'Нет прошедших экскурсий на выбранную дату',
                            isPast: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MyBookingsSubTab extends ConsumerStatefulWidget {
  const _MyBookingsSubTab({required this.user});

  final User user;

  @override
  ConsumerState<_MyBookingsSubTab> createState() => _MyBookingsSubTabState();
}

class _MyBookingsSubTabState extends ConsumerState<_MyBookingsSubTab>
    with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsFutureProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Не удалось загрузить бронирования: $error'),
      ),
      data: (groups) {
        // Фильтруем только бронирования текущего пользователя
        final myGroups = groups
            .map((group) {
              final myBookings = group.bookings
                  .where((booking) => booking.bookedBy == widget.user.id)
                  .toList();
              if (myBookings.isEmpty) return null;
              return BookingGroup(
                excursion: group.excursion,
                bookings: myBookings,
              );
            })
            .whereType<BookingGroup>()
            .toList();

        // Разделяем на новые (будущие) и старые (прошедшие)
        final now = DateTime.now();
        final newGroups = <BookingGroup>[];
        final oldGroups = <BookingGroup>[];

        final todayStart = DateTime(now.year, now.month, now.day);

        for (final group in myGroups) {
          if (group.excursion.dateTime.isBefore(todayStart)) {
            oldGroups.add(group);
          } else {
            newGroups.add(group);
          }
        }

        // Сортируем внутри групп по датам
        newGroups.sort(
            (a, b) => a.excursion.dateTime.compareTo(b.excursion.dateTime));
        oldGroups.sort(
            (a, b) => b.excursion.dateTime.compareTo(a.excursion.dateTime));

        // Фильтруем по выбранной дате
        final filterByDate = (List<BookingGroup> groups) {
          if (_selectedDate == null) return groups;
          return groups.where((group) {
            final excursionDate = DateTime(
              group.excursion.dateTime.year,
              group.excursion.dateTime.month,
              group.excursion.dateTime.day,
            );
            final selectedDateOnly = DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
            );
            return excursionDate == selectedDateOnly;
          }).toList();
        };

        final filteredNewGroups = filterByDate(newGroups);
        final filteredOldGroups = filterByDate(oldGroups);

        // Группируем по датам экскурсий
        final groupByDate = (List<BookingGroup> groups) {
          final dateGroups = <DateTime, List<BookingGroup>>{};
          for (final group in groups) {
            final date = DateTime(
              group.excursion.dateTime.year,
              group.excursion.dateTime.month,
              group.excursion.dateTime.day,
            );
            dateGroups.putIfAbsent(date, () => []).add(group);
          }
          return dateGroups;
        };

        final newDateGroups = groupByDate(filteredNewGroups);
        final oldDateGroups = groupByDate(filteredOldGroups);
        final sortedNewDates = newDateGroups.keys.toList()..sort();
        final sortedOldDates = oldDateGroups.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        final subFormatter = DateFormat('dd.MM.yyyy HH:mm');
        final dateFormatter = DateFormat('EEEE, dd MMMM yyyy', 'ru_RU');
        final timeFormatter = DateFormat('HH:mm');

        Widget buildDateGroupList(Map<DateTime, List<BookingGroup>> dateGroups,
            List<DateTime> sortedDates) {
          return Column(
            children: sortedDates.asMap().entries.map((dateEntry) {
              final dateIndex = dateEntry.key;
              final date = dateEntry.value;
              final groups = dateGroups[date]!;
              final totalBookings =
                  groups.fold<int>(0, (sum, g) => sum + g.bookings.length);
              return _ExpandableCard(
                color: dateIndex % 2 == 0 ? Colors.grey.shade50 : Colors.white,
                child: ExpansionTile(
                  title: Text(
                    dateFormatter.format(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  subtitle: Text(
                      '$totalBookings ${totalBookings == 1 ? 'бронирование' : totalBookings < 5 ? 'бронирования' : 'бронирований'}'),
                  children: groups.map((group) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.excursion.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 4),
                          ...group.bookings.asMap().entries.map((entry) {
                            final bookingIndex = entry.key;
                            final booking = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: bookingIndex % 2 == 0
                                    ? Colors.grey.shade100
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.shade100,
                                  child: Text(
                                    '${booking.seat.seatNumber}',
                                    style: TextStyle(
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  '${booking.customerName} • ${booking.customerPhone}',
                                ),
                                subtitle: Text(
                                  '${booking.passengerType.name} • ${subFormatter.format(booking.excursion.dateTime)}',
                                ),
                                trailing: Text(
                                  '${booking.price.toStringAsFixed(2)} ₽',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Мои бронирования',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _selectedDate == null
                          ? 'Выбрать дату'
                          : DateFormat('dd.MM.yyyy').format(_selectedDate!),
                    ),
                    onPressed: () => _selectDate(context),
                  ),
                ],
              ),
            ),
            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Сбросить фильтр'),
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                    });
                  },
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Новые'),
                Tab(text: 'Прошедшие'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingsList(
                    context,
                    ref,
                    sortedNewDates,
                    newDateGroups,
                    dateFormatter,
                    timeFormatter,
                    subFormatter,
                    'Нет ваших новых бронирований',
                  ),
                  _buildBookingsList(
                    context,
                    ref,
                    sortedOldDates,
                    oldDateGroups,
                    dateFormatter,
                    timeFormatter,
                    subFormatter,
                    'Нет ваших прошедших бронирований',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    WidgetRef ref,
    List<DateTime> sortedDates,
    Map<DateTime, List<BookingGroup>> dateGroups,
    DateFormat dateFormatter,
    DateFormat timeFormatter,
    DateFormat subFormatter,
    String emptyMessage,
  ) {
    if (dateGroups.isEmpty || sortedDates.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bookingsFutureProvider);
          await ref.read(bookingsFutureProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyMessage),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bookingsFutureProvider);
        await ref.read(bookingsFutureProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: sortedDates.asMap().entries.map((dateEntry) {
          final dateIndex = dateEntry.key;
          final date = dateEntry.value;
          final groups = dateGroups[date]!;
          final totalBookings =
              groups.fold<int>(0, (sum, g) => sum + g.bookings.length);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: dateIndex % 2 == 0 ? Colors.grey.shade50 : Colors.white,
            child: ExpansionTile(
              title: Text(
                dateFormatter.format(date),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              subtitle: Text(
                  '$totalBookings ${totalBookings == 1 ? 'бронирование' : totalBookings < 5 ? 'бронирования' : 'бронирований'}'),
              children: groups.map((group) {
                // Собираем уникальные имена пользователей, которые забронировали места
                final bookedByNames = group.bookings
                    .where((b) =>
                        b.bookedByName != null && b.bookedByName!.isNotEmpty)
                    .map((b) => b.bookedByName!)
                    .toSet()
                    .toList();

                final bookedByText = bookedByNames.isNotEmpty
                    ? ' • ${bookedByNames.join(', ')}'
                    : '';

                // Группируем места по сотрудникам, которые их забронировали
                final bookingsByUser = <String, List<BookingItem>>{};
                for (final booking in group.bookings) {
                  final userName = booking.bookedByName?.isNotEmpty == true
                      ? booking.bookedByName!
                      : 'Неизвестный';
                  bookingsByUser.putIfAbsent(userName, () => []).add(booking);
                }

                return _ExpandableCard(
                  useCard: false,
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(group.excursion.title),
                    subtitle: Text(
                      '${timeFormatter.format(group.excursion.dateTime)}$bookedByText • ${group.bookings.length} мест${group.bookings.length > 1 ? 'а' : ''}${group.excursion.maxSeats != null ? ' из ${group.excursion.maxSeats}' : ''}',
                    ),
                    children: [
                      // Группируем по сотрудникам
                      ...bookingsByUser.entries.map(
                        (entry) {
                          final isLastGroup =
                              entry == bookingsByUser.entries.last;
                          return Column(
                            children: [
                              // Сворачиваемая группа по сотруднику
                              _ExpandableCard(
                                useCard: false,
                                margin: EdgeInsets.zero,
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  childrenPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${entry.key} — ${entry.value.length} мест${entry.value.length > 1 ? 'а' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  children: entry.value
                                      .map(
                                        (booking) => ListTile(
                                          dense: true,
                                          title: Text(
                                              'Место ${booking.seat.seatNumber}'),
                                          subtitle: Text(
                                              'Бронировано: ${subFormatter.format(booking.bookedAt)}'),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.cancel),
                                            tooltip: 'Отменить',
                                            onPressed: () => _cancelBooking(
                                                context, ref, booking.id),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                              // Разделитель между группами (кроме последней)
                              if (!isLastGroup)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _cancelBooking(
    BuildContext context,
    WidgetRef ref,
    int bookingId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const CancellationReasonDialog(),
    );

    if (reason == null) {
      return;
    }

    try {
      await ref
          .read(bookingsRepositoryProvider)
          .cancelBooking(bookingId, reason: reason);
      ref.invalidate(bookingsFutureProvider);
      ref.invalidate(excursionsFutureProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Бронирование отменено'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось отменить: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

class _AllBookingsSubTab extends ConsumerStatefulWidget {
  const _AllBookingsSubTab();

  @override
  ConsumerState<_AllBookingsSubTab> createState() => _AllBookingsSubTabState();
}

class _AllBookingsSubTabState extends ConsumerState<_AllBookingsSubTab>
    with SingleTickerProviderStateMixin {
  DateTime? _selectedDate;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsFutureProvider);

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Не удалось загрузить бронирования: $error'),
      ),
      data: (groups) {
        // Разделяем на новые (будущие) и старые (прошедшие)
        final now = DateTime.now();
        final newGroups = <BookingGroup>[];
        final oldGroups = <BookingGroup>[];

        for (final group in groups) {
          if (group.excursion.dateTime.isAfter(now)) {
            newGroups.add(group);
          } else {
            oldGroups.add(group);
          }
        }

        // Сортируем внутри групп по датам
        newGroups.sort(
            (a, b) => a.excursion.dateTime.compareTo(b.excursion.dateTime));
        oldGroups.sort(
            (a, b) => b.excursion.dateTime.compareTo(a.excursion.dateTime));

        // Группируем по датам экскурсий
        final groupByDate = (List<BookingGroup> groups) {
          final dateGroups = <DateTime, List<BookingGroup>>{};
          for (final group in groups) {
            final date = DateTime(
              group.excursion.dateTime.year,
              group.excursion.dateTime.month,
              group.excursion.dateTime.day,
            );
            dateGroups.putIfAbsent(date, () => []).add(group);
          }
          return dateGroups;
        };

        final newDateGroups = groupByDate(newGroups);
        final oldDateGroups = groupByDate(oldGroups);
        final sortedNewDates = newDateGroups.keys.toList()..sort();
        final sortedOldDates = oldDateGroups.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        // Фильтруем по выбранной дате
        final filterByDate = (Map<DateTime, List<BookingGroup>> dateGroups) {
          if (_selectedDate == null) return dateGroups;
          final selectedDateOnly = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
          );
          return dateGroups.entries
              .where((entry) => entry.key == selectedDateOnly)
              .fold<Map<DateTime, List<BookingGroup>>>(
            {},
            (map, entry) => map..[entry.key] = entry.value,
          );
        };

        final filteredNewDateGroups =
            _selectedDate == null ? newDateGroups : filterByDate(newDateGroups);
        final filteredOldDateGroups =
            _selectedDate == null ? oldDateGroups : filterByDate(oldDateGroups);

        final subFormatter = DateFormat('dd.MM.yyyy HH:mm');
        final dateFormatter = DateFormat('EEEE, dd MMMM yyyy', 'ru_RU');
        final timeFormatter = DateFormat('HH:mm');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Все бронирования',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(
                      _selectedDate == null
                          ? 'Выбрать дату'
                          : DateFormat('dd.MM.yyyy').format(_selectedDate!),
                    ),
                    onPressed: () => _selectDate(context),
                  ),
                ],
              ),
            ),
            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextButton.icon(
                  icon: const Icon(Icons.clear, size: 18),
                  label: const Text('Сбросить фильтр'),
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                    });
                  },
                ),
              ),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Новые'),
                Tab(text: 'Прошедшие'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildBookingsList(
                    context,
                    ref,
                    sortedNewDates
                        .where(
                            (date) => filteredNewDateGroups.containsKey(date))
                        .toList(),
                    filteredNewDateGroups,
                    dateFormatter,
                    timeFormatter,
                    subFormatter,
                    'Нет новых бронирований',
                  ),
                  _buildBookingsList(
                    context,
                    ref,
                    sortedOldDates
                        .where(
                            (date) => filteredOldDateGroups.containsKey(date))
                        .toList(),
                    filteredOldDateGroups,
                    dateFormatter,
                    timeFormatter,
                    subFormatter,
                    'Нет прошедших бронирований',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBookingsList(
    BuildContext context,
    WidgetRef ref,
    List<DateTime> sortedDates,
    Map<DateTime, List<BookingGroup>> dateGroups,
    DateFormat dateFormatter,
    DateFormat timeFormatter,
    DateFormat subFormatter,
    String emptyMessage,
  ) {
    if (dateGroups.isEmpty || sortedDates.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bookingsFutureProvider);
          await ref.read(bookingsFutureProvider.future);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyMessage),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bookingsFutureProvider);
        await ref.read(bookingsFutureProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: sortedDates.asMap().entries.map((dateEntry) {
          final dateIndex = dateEntry.key;
          final date = dateEntry.value;
          final groups = dateGroups[date]!;
          final totalBookings =
              groups.fold<int>(0, (sum, g) => sum + g.bookings.length);
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: dateIndex % 2 == 0 ? Colors.grey.shade50 : Colors.white,
            child: ExpansionTile(
              title: Text(
                dateFormatter.format(date),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              subtitle: Text(
                  '$totalBookings ${totalBookings == 1 ? 'бронирование' : totalBookings < 5 ? 'бронирования' : 'бронирований'}'),
              children: groups.map((group) {
                // Собираем уникальные имена пользователей, которые забронировали места
                final bookedByNames = group.bookings
                    .where((b) =>
                        b.bookedByName != null && b.bookedByName!.isNotEmpty)
                    .map((b) => b.bookedByName!)
                    .toSet()
                    .toList();

                final bookedByText = bookedByNames.isNotEmpty
                    ? ' • ${bookedByNames.join(', ')}'
                    : '';

                // Группируем места по сотрудникам, которые их забронировали
                final bookingsByUser = <String, List<BookingItem>>{};
                for (final booking in group.bookings) {
                  final userName = booking.bookedByName?.isNotEmpty == true
                      ? booking.bookedByName!
                      : 'Неизвестный';
                  bookingsByUser.putIfAbsent(userName, () => []).add(booking);
                }

                return _ExpandableCard(
                  useCard: false,
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(group.excursion.title),
                    subtitle: Text(
                      '${timeFormatter.format(group.excursion.dateTime)}$bookedByText • ${group.bookings.length} мест${group.bookings.length > 1 ? 'а' : ''}${group.excursion.maxSeats != null ? ' из ${group.excursion.maxSeats}' : ''}',
                    ),
                    children: [
                      // Группируем по сотрудникам
                      ...bookingsByUser.entries.map(
                        (entry) {
                          final isLastGroup =
                              entry == bookingsByUser.entries.last;
                          return Column(
                            children: [
                              _ExpandableCard(
                                useCard: false,
                                margin: EdgeInsets.zero,
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  childrenPadding: EdgeInsets.zero,
                                  title: Text(
                                    '${entry.key} — ${entry.value.length} мест${entry.value.length > 1 ? 'а' : ''}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  children: entry.value.asMap().entries.map(
                                    (bookingEntry) {
                                      final booking = bookingEntry.value;
                                      final bookingIndex = bookingEntry.key;
                                      return Container(
                                        color: bookingIndex % 2 == 0
                                            ? Colors.grey.shade100
                                            : Colors.white,
                                        child: ListTile(
                                          title: Text(
                                              'Место ${booking.seat.seatNumber}'),
                                          subtitle: Text(
                                              'Бронировано: ${subFormatter.format(booking.bookedAt)}'),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.cancel),
                                            tooltip: 'Отменить',
                                            onPressed: () => _cancelBooking(
                                                context, ref, booking.id),
                                          ),
                                        ),
                                      );
                                    },
                                  ).toList(),
                                ),
                              ),
                              // Разделитель между группами (кроме последней)
                              if (!isLastGroup)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  indent: 16,
                                  endIndent: 16,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _cancelBooking(
    BuildContext context,
    WidgetRef ref,
    int bookingId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const CancellationReasonDialog(),
    );

    if (reason == null) {
      return;
    }

    try {
      await ref
          .read(bookingsRepositoryProvider)
          .cancelBooking(bookingId, reason: reason);
      ref.invalidate(bookingsFutureProvider);
      ref.invalidate(excursionsFutureProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Бронирование отменено'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось отменить: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

class _ExcursionsTableHeader extends StatelessWidget {
  const _ExcursionsTableHeader({
    this.showActionButtons = true,
  });

  final bool showActionButtons;

  static const int titleFlex = 9;
  static const int driverFlex = 3;
  static const int guideFlex = 3;
  static const double actionsWidth = 196;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade600,
          letterSpacing: 0.2,
          fontSize: 11,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 520;
        return Row(
          children: [
            Expanded(
              flex: titleFlex,
              child: Text('Название', style: style),
            ),
            Expanded(
              flex: driverFlex,
              child: Text('Вод', style: style, textAlign: TextAlign.center),
            ),
            Expanded(
              flex: guideFlex,
              child: Text('Экс', style: style, textAlign: TextAlign.center),
            ),
            if (showActionButtons && !isCompact)
              const SizedBox(width: actionsWidth),
          ],
        );
      },
    );
  }
}

class _ExpandableCard extends StatefulWidget {
  const _ExpandableCard({
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.color,
    this.useCard = true,
  });

  final ExpansionTile child;
  final EdgeInsetsGeometry margin;
  final Color? color;
  final bool useCard;

  @override
  State<_ExpandableCard> createState() => _ExpandableCardState();
}

class _ExpandableCardState extends State<_ExpandableCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final expansionTile = ExpansionTile(
      title: widget.child.title,
      subtitle: widget.child.subtitle,
      leading: widget.child.leading,
      trailing: widget.child.trailing,
      tilePadding: widget.child.tilePadding,
      childrenPadding: widget.child.childrenPadding,
      initiallyExpanded: widget.child.initiallyExpanded,
      onExpansionChanged: (expanded) {
        setState(() {
          _isExpanded = expanded;
        });
        widget.child.onExpansionChanged?.call(expanded);
      },
      children: widget.child.children,
    );

    if (!widget.useCard) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _isExpanded
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: _isExpanded ? 2 : 0,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: expansionTile,
      );
    }

    return Card(
      margin: widget.margin,
      color: widget.color,
      elevation: _isExpanded ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _isExpanded
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: _isExpanded ? 2 : 0,
        ),
      ),
      child: expansionTile,
    );
  }
}

class _AdminExcursionCard extends ConsumerWidget {
  const _AdminExcursionCard({
    required this.excursion,
    required this.formatter,
    required this.user,
    required this.index,
    required this.showActionButtons,
  });

  final Excursion excursion;
  final DateFormat formatter;
  final User user;
  final int index;
  final bool showActionButtons;

  static const int _titleFlex = _ExcursionsTableHeader.titleFlex;
  static const int _driverFlex = _ExcursionsTableHeader.driverFlex;
  static const int _guideFlex = _ExcursionsTableHeader.guideFlex;
  static const double _actionsWidth = _ExcursionsTableHeader.actionsWidth;

  String get _targetDate => DateFormat('yyyy-MM-dd').format(excursion.dateTime);

  String get _targetTime => DateFormat('HH:mm').format(excursion.dateTime);

  /// Фильтрует персонал по дате/времени экскурсии
  List<ExcursionStaff> get _filteredStaff {
    return excursion.assignedStaff.where((staff) {
      // Показываем назначения без даты (на все даты) или с совпадающей датой
      final matchesDate =
          staff.excursionDate == null || staff.excursionDate == _targetDate;
      final matchesTime = staff.time == null || staff.time == _targetTime;
      return matchesDate && matchesTime;
    }).toList();
  }

  List<ExcursionBusAssignment> get _filteredBusAssignments {
    return excursion.busAssignments.where((assignment) {
      final matchesDate = assignment.excursionDate == null ||
          assignment.excursionDate == _targetDate;
      final matchesTime =
          assignment.time == null || assignment.time == _targetTime;
      return matchesDate && matchesTime;
    }).toList()
      ..sort((a, b) => a.seatFrom.compareTo(b.seatFrom));
  }

  List<ExcursionStaff> get _driversForSlot {
    return _filteredStaff
        .where((member) => member.roleInExcursion == 'driver')
        .toList();
  }

  List<ExcursionStaff> get _guidesForSlot {
    final realGuides = _filteredStaff
        .where((member) => member.roleInExcursion == 'guide')
        .toList();

    if (realGuides.isNotEmpty) {
      return realGuides;
    }

    return _driversForSlot
        .map((member) => member.asAutoGuideFromDriver())
        .toList();
  }

  String _staffNames(List<ExcursionStaff> staff) {
    if (staff.isEmpty) {
      return '—';
    }

    return staff.map((member) => member.name).join(', ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Определяем, доступна ли экскурсия для бронирования
    // Отмененные экскурсии недоступны для бронирования
    final isAvailable = excursion.availableSeatsCount > 0 &&
        !excursion.isPast &&
        !excursion.isCancelled;

    // Определяем цвет фона: отмененные - красноватый, внеплановые - светло-желтый, недоступные - серый, остальные - чередующийся
    Color? cardColor;
    if (excursion.isCancelled) {
      cardColor = Colors.red.shade50; // Светло-красный для отмененных
    } else if (!isAvailable) {
      cardColor = Colors.grey.shade200; // Серый фон для недоступных
    } else if (excursion.isUnscheduled) {
      cardColor = Colors.amber.shade50; // Светло-желтый для внеплановых
    } else {
      // Чередующийся фон для четных/нечетных строк
      cardColor = index % 2 == 0 ? Colors.grey.shade100 : Colors.white;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            final information = _buildInformationRow(context);
            if (!showActionButtons) {
              return information;
            }

            final actions = _buildActionButtons(context, ref, isCompact);
            if (isCompact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  information,
                  const SizedBox(height: 6),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: information),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInformationRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: _titleFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      excursion.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.black87,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (excursion.isCancelled)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ОТМЕНЕНА',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${formatter.format(excursion.dateTime)} • занято ${excursion.bookedSeatsCount}/${excursion.maxSeats}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey.shade600,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: _driverFlex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _staffNames(_driversForSlot),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 11, height: 1.25),
            ),
          ),
        ),
        Expanded(
          flex: _guideFlex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              _staffNames(_guidesForSlot),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontSize: 11, height: 1.25),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    bool isCompact,
  ) {
    return SizedBox(
      width: isCompact ? double.infinity : _actionsWidth,
      child: Row(
        mainAxisAlignment:
            isCompact ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 20),
            tooltip: 'Фотографии экскурсии',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: () => showExcursionGalleryDialog(
              context: context,
              ref: ref,
              excursion: excursion,
            ),
          ),
          if (1 == 2)
            IconButton(
              icon: const Icon(Icons.directions_bus, size: 20),
              tooltip: 'Автобусы экскурсии',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              onPressed: excursion.isCancelled
                  ? null
                  : () => _showExcursionBuses(context, ref),
            ),
          IconButton(
            icon: const Icon(Icons.list, size: 20),
            tooltip:
                excursion.isCancelled ? 'Экскурсия отменена' : 'Выбрать места',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: (excursion.isCancelled || excursion.busSeats.isEmpty)
                ? null
                : () => _showSeatSheet(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.event_seat, size: 20),
            tooltip:
                excursion.isCancelled ? 'Экскурсия отменена' : 'Схема рассадки',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: (excursion.busSeats.isEmpty || excursion.isCancelled)
                ? null
                : () => _showSeatingChart(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.description_outlined, size: 20),
            tooltip: excursion.isCancelled ? 'Экскурсия отменена' : 'Ведомость',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed: (excursion.busSeats.isEmpty || excursion.isCancelled)
                ? null
                : () => _showManifestDialog(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.person_add, size: 20),
            tooltip: excursion.isCancelled
                ? 'Экскурсия отменена'
                : 'Назначить персонал',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            onPressed:
                excursion.isCancelled ? null : () => _assignStaff(context, ref),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStaffIndicators(BuildContext context, WidgetRef ref) {
    final staff = _filteredStaff;
    if (staff.isEmpty) return [];

    final mode = ref.watch(staffIndicatorModeProvider);
    final drivers =
        staff.where((member) => member.roleInExcursion == 'driver').toList();
    final realGuides =
        staff.where((member) => member.roleInExcursion == 'guide').toList();
    final guides = realGuides.isNotEmpty
        ? realGuides
        : drivers.map((member) => member.asAutoGuideFromDriver()).toList();
    final others = staff
        .where((member) =>
            member.roleInExcursion != 'driver' &&
            member.roleInExcursion != 'guide')
        .toList();

    if (mode == StaffIndicatorMode.combined && 1 == 2) {
      final totalCount = staff.length;
      return [
        _buildStaffChip(
          context: context,
          staff: staff,
          tooltip: 'Назначено: $totalCount',
          icon: Icons.people,
          color: Colors.blue,
          countLabel: '$totalCount',
        ),
      ];
    }

    final chips_old = <Widget>[
      if (drivers.isNotEmpty)
        _buildStaffChip(
          context: context,
          staff: drivers,
          tooltip: 'Водители: ${drivers.length}',
          icon: Icons.directions_bus,
          color: Colors.indigo,
          countLabel: '${drivers.length}',
        ),
      if (guides.isNotEmpty)
        _buildStaffChip(
          context: context,
          staff: guides,
          tooltip: realGuides.isNotEmpty
              ? 'Экскурсоводы: ${guides.length}'
              : 'Экскурсоводы: ${guides.length} (автоматически из водителей)',
          icon: Icons.record_voice_over,
          color: Colors.teal,
          countLabel: '${guides.length}',
        ),
      if (others.isNotEmpty)
        _buildStaffChip(
          context: context,
          staff: others,
          tooltip: 'Другой персонал: ${others.length}',
          icon: Icons.people_outline,
          color: Colors.blueGrey,
          countLabel: '${others.length}',
        ),
    ];
    final chips = <Widget>[];
    // На случай необычных ролей — хотя бы общий индикатор
    return chips.isNotEmpty ? chips : [];
/*            _buildStaffChip(
              context: context,
              staff: staff,
              tooltip: 'Назначено: ${staff.length}',
              icon: Icons.people,
              color: Colors.blue,
              countLabel: '${staff.length}',
            ),
          ];*/
  }

  Widget _buildStaffChip({
    required BuildContext context,
    required List<ExcursionStaff> staff,
    required String tooltip,
    required IconData icon,
    required Color color,
    required String countLabel,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => _showAllStaffDialog(context, staff),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  countLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllStaffDialog(BuildContext context, List<ExcursionStaff> staff) {
    final staffByRole = <String, List<ExcursionStaff>>{};
    final drivers =
        staff.where((member) => member.roleInExcursion == 'driver').toList();
    final realGuides =
        staff.where((member) => member.roleInExcursion == 'guide').toList();
    final effectiveStaff = <ExcursionStaff>[
      ...staff,
      if (realGuides.isEmpty)
        ...drivers.map((member) => member.asAutoGuideFromDriver()),
    ];

    for (final member in effectiveStaff) {
      staffByRole.putIfAbsent(member.roleInExcursion, () => []).add(member);
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.people, color: Colors.blueGrey.shade700),
            const SizedBox(width: 8),
            const Text('Назначенный персонал'),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: staffByRole.entries.map((entry) {
              final role = entry.key;
              final members = entry.value;
              final label = _roleLabel(role);
              final icon = _roleIcon(role);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Row(
                      children: [
                        Icon(icon, size: 18, color: Colors.blueGrey.shade700),
                        const SizedBox(width: 6),
                        Text(
                          '$label (${members.length})',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...members.map(
                    (member) => Padding(
                      padding:
                          const EdgeInsets.only(left: 24, top: 2, bottom: 2),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              member.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (member.isAutoGuideFromDriver) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.directions_bus,
                              size: 14,
                              color: Colors.indigo.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'авто из водителя',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.indigo.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'driver':
        return Icons.directions_bus;
      case 'guide':
        return Icons.record_voice_over;
      default:
        return Icons.person;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'driver':
        return 'Водители';
      case 'guide':
        return 'Экскурсоводы';
      default:
        return 'Персонал';
    }
  }

  Future<void> _book(
    BuildContext context,
    WidgetRef ref, {
    List<int>? preselectedSeats,
  }) async {
    // Проверяем, не отменена ли экскурсия
    if (excursion.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Эта экскурсия отменена. Бронирование невозможно.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }

    final stops = await ref
        .read(stopsRepositoryProvider)
        .fetchStopsForExcursion(excursion.id);

    // Получаем список пользователей для бронирования от лица продавца/партнера
    final allUsers = await ref.read(allUsersFutureProvider.future);
    final sellers = allUsers
        .where(
          (user) =>
              user.roleId == 2 || // role_id 2 = продавец
              user.roleId == 4 || // role_id 4 = партнер
              user.roleName.toLowerCase().contains('продав') ||
              user.roleName.toLowerCase().contains('партнер') ||
              user.roleName.toLowerCase().contains('партн') ||
              user.roleName.toLowerCase().contains('seller') ||
              user.roleName.toLowerCase().contains('partner'),
        )
        .toList();

    final result = await showDialog<BookingDialogResult>(
      context: context,
      builder: (dialogContext) => BookingDialog(
        stops: stops,
        tariffs: excursion.tariffs,
        initialSeatNumbers: preselectedSeats ?? const [],
        lockSeatSelection: (preselectedSeats?.isNotEmpty ?? false),
        sellers: sellers, // Передаем список продавцов
        currentUserId: user.id, // ID текущего админа
        excursionTitle: excursion.title,
      ),
    );

    if (result == null) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      // Извлекаем weekday, time и конкретную дату из dateTime экскурсии
      // DateTime.weekday возвращает ISO weekday (1 = Monday, 7 = Sunday)
      final weekday = excursion.dateTime.weekday; // 1-7
      final time = DateFormat('HH:mm').format(excursion.dateTime);
      final excursionDate = DateFormat('yyyy-MM-dd').format(excursion.dateTime);

      // Используем новый формат если доступен, иначе старый
      final payload = result.seats != null && result.seats!.isNotEmpty
          ? BookSeatPayload(
              excursionId: excursion.id,
              seats: result.seats!,
              customerName: result.customerName,
              customerPhone: result.customerPhone,
              stopId: result.stopId,
              weekday: weekday,
              time: time,
              excursionDate: excursionDate,
              bookedById: result.bookedById, // ID выбранного продавца
            )
          : BookSeatPayload(
              excursionId: excursion.id,
              seatNumbers: result.seatNumbers,
              customerName: result.customerName,
              customerPhone: result.customerPhone,
              passengerType: result.passengerType,
              stopId: result.stopId,
              weekday: weekday,
              time: time,
              excursionDate: excursionDate,
              bookedById: result.bookedById, // ID выбранного продавца
            );

      final response =
          await ref.read(bookingsRepositoryProvider).bookSeats(payload);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response.message.isNotEmpty
                ? response.message
                : 'Бронирование выполнено',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
      ref.invalidate(bookingsFutureProvider);
      ref.invalidate(excursionsFutureProvider);

      // Сохраняем/открываем PDF через backend
      try {
        final bookingId = response.firstBookingId;
        if (bookingId != null) {
          // Получаем все ID бронирований из ответа
          final allBookingIds = response.bookings
              ?.map((b) => b['id'] as int?)
              .whereType<int>()
              .toList();

          // Логируем для отладки
          print('PDF generation: bookingId=$bookingId');
          print('PDF generation: bookings response=${response.bookings}');
          print(
              'PDF generation: allBookingIds=$allBookingIds, count=${allBookingIds?.length ?? 0}');

          // Проверяем, что список не пустой
          if (allBookingIds == null || allBookingIds.isEmpty) {
            print(
                'WARNING: allBookingIds is null or empty! Using single bookingId: $bookingId');
          }

          // Скачиваем PDF как байты, передавая все ID бронирований
          final pdfBytes =
              await ref.read(bookingsRepositoryProvider).downloadTicketPdf(
                    bookingId,
                    bookingIds: allBookingIds?.isNotEmpty == true
                        ? allBookingIds
                        : null,
                  );
          // Сохраняем/отправляем PDF (на мобильных) или скачиваем (на веб)
          await PdfDownloader.saveAndSharePdf(
            pdfBytes: pdfBytes,
            filename: 'ticket-$bookingId.pdf',
          );
        }
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Не удалось сохранить билет: $error'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ошибка бронирования: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _showSeatSheet(BuildContext context, WidgetRef ref) async {
    if (excursion.isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Эта экскурсия отменена. Бронирование невозможно.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }

    List<BusSeat> seatsToShow = excursion.busSeats;
    final busAssignmentLines = _filteredBusAssignments.map((assignment) {
      final bus = assignment.bus;
      final driverName = assignment.driver?.name;
      final busText = bus == null
          ? 'Автобус'
          : 'Автобус №${bus.number}${bus.model != null ? " · ${bus.model}" : ""}';
      final seatsText = 'места ${assignment.seatFrom}-${assignment.seatTo}';
      final driverText =
          driverName == null || driverName.isEmpty ? '' : ' · $driverName';
      return '$busText · $seatsText$driverText';
    }).toList();
    final assignedSeatNumbers = <int>{
      for (final assignment in _filteredBusAssignments)
        for (int seat = assignment.seatFrom; seat <= assignment.seatTo; seat++)
          seat,
    };

    if (seatsToShow.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет данных о местах'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    final selectedSeats = <int>{};

    if (!context.mounted) return;

    final result = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Выбор мест'),
              if (busAssignmentLines.isNotEmpty)
                ...busAssignmentLines.map(
                  (line) => Text(
                    line,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                )
              else
                const Text(
                  'Автобус на эту дату пока не назначен. Места остаются общими.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              if (busAssignmentLines.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.indigo,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Рамкой выделены места, уже включённые в автобус',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: seatsToShow.map((seat) {
                  final isAvailable = seat.status == 'available';
                  final isSelected = selectedSeats.contains(seat.seatNumber);
                  final isAssignedToBus =
                      assignedSeatNumbers.contains(seat.seatNumber);
                  final color = isSelected
                      ? Colors.blue.shade300
                      : isAvailable
                          ? Colors.green.shade200
                          : Colors.red.shade200;
                  return InkWell(
                    onTap: isAvailable
                        ? () {
                            setState(() {
                              if (isSelected) {
                                selectedSeats.remove(seat.seatNumber);
                              } else {
                                selectedSeats.add(seat.seatNumber);
                              }
                            });
                          }
                        : null,
                    child: Chip(
                      label: Text('${seat.seatNumber}'),
                      backgroundColor: color,
                      shape: StadiumBorder(
                        side: isAssignedToBus
                            ? const BorderSide(
                                color: Colors.indigo,
                                width: 2,
                              )
                            : BorderSide.none,
                      ),
                      labelStyle: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            if (selectedSeats.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => selectedSeats.clear()),
                child: const Text('Очистить'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
            FilledButton(
              onPressed: selectedSeats.isNotEmpty
                  ? () => Navigator.of(dialogContext)
                      .pop(selectedSeats.toList()..sort())
                  : null,
              child: Text('Выбрать (${selectedSeats.length})'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _book(context, ref, preselectedSeats: result);
    }
  }

  Future<void> _showSeatingChart(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => _AdminSeatingChartSheet(
        excursionId: excursion.id,
        excursionDate: excursion.dateTime,
      ),
    );
  }

  Future<void> _showManifestDialog(BuildContext context, WidgetRef ref) async {
    Excursion currentExcursion = excursion;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentExcursion.title,
                style: Theme.of(dialogContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${formatter.format(currentExcursion.dateTime)} • занято ${currentExcursion.bookedSeatsCount}/${currentExcursion.maxSeats}',
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                      color: Colors.blueGrey.shade600,
                    ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: _AdminExcursionManifestContent(
                excursion: currentExcursion,
                hasDriverAssigned: _driversForSlot.isNotEmpty,
                hasGuideAssigned: _guidesForSlot.isNotEmpty,
                onEditActualAmount: () async {
                  final dialogResult = await _showAdminActualAmountDialog(
                    dialogContext,
                    initialAmount: currentExcursion.actualAmount,
                  );

                  if (dialogResult == null) {
                    return;
                  }

                  try {
                    final updated = await ref
                        .read(excursionsRepositoryProvider)
                        .updateActualAmount(
                          excursionId: currentExcursion.id,
                          actualAmount: dialogResult.value,
                        );
                    if (!dialogContext.mounted) {
                      return;
                    }
                    setDialogState(() {
                      currentExcursion = updated;
                    });
                    ref.invalidate(excursionsFutureProvider);
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Фактическая сумма сохранена'),
                        behavior: SnackBarBehavior.floating,
                        margin: EdgeInsets.all(16),
                      ),
                    );
                  } catch (error) {
                    if (!dialogContext.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text('Не удалось сохранить сумму: $error'),
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
          actions: [
            FilledButton.icon(
              onPressed: () async {
                try {
                  final pdfBytes = await _buildManifestPdfBytes(
                    excursion: currentExcursion,
                    formatter: formatter,
                    hasDriverAssigned: _driversForSlot.isNotEmpty,
                    hasGuideAssigned: _guidesForSlot.isNotEmpty,
                  );
                  await PdfDownloader.saveAndSharePdf(
                    pdfBytes: pdfBytes,
                    filename:
                        'manifest-${currentExcursion.id}-${DateFormat('yyyyMMdd-HHmm').format(currentExcursion.dateTime)}.pdf',
                  );
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Не удалось сформировать PDF: $error'),
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('PDF'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assignStaff(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => AssignStaffSheet(excursion: excursion),
    );
    if (result == true) {
      ref.invalidate(excursionsFutureProvider);
    }
  }

  Future<void> _showExcursionBuses(BuildContext context, WidgetRef ref) async {
    List<Bus> allBuses = [];
    try {
      allBuses =
          await ref.read(busesRepositoryProvider).fetchBuses(isActive: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки автобусов: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    if (!context.mounted) return;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (dialogContext) => _ExcursionBusesSheet(
        excursionId: excursion.id,
        excursionTitle: excursion.title,
        excursionDate: _targetDate,
        excursionTime: _targetTime,
        currentAssignments: _filteredBusAssignments,
        availableBuses: allBuses,
      ),
    );

    if (updated == true) {
      ref.invalidate(excursionsFutureProvider);
    }
  }
}

class _AdminExcursionManifestContent extends StatelessWidget {
  const _AdminExcursionManifestContent({
    required this.excursion,
    required this.hasDriverAssigned,
    required this.hasGuideAssigned,
    required this.onEditActualAmount,
  });

  final Excursion excursion;
  final bool hasDriverAssigned;
  final bool hasGuideAssigned;
  final VoidCallback onEditActualAmount;

  @override
  Widget build(BuildContext context) {
    final stops = _buildAdminManifestStops(excursion.busSeats);
    final manifestStaff = _filterManifestStaffForSlot(excursion);
    final driverAssignments = manifestStaff
        .where((member) => member.roleInExcursion == 'driver')
        .toList();
    final guideAssignments = manifestStaff
        .where((member) => member.roleInExcursion == 'guide')
        .toList();
    final transportCost = _resolveAdminStaffCost(
      excursion,
      'driver',
      isAssigned: hasDriverAssigned,
      assignedStaff:
          driverAssignments.isNotEmpty ? driverAssignments.first : null,
    );
    final guideCost = _resolveAdminStaffCost(
      excursion,
      'guide',
      isAssigned: hasGuideAssigned,
      assignedStaff:
          guideAssignments.isNotEmpty ? guideAssignments.first : null,
    );
    final entryTicketsCost = _resolveAdminEntryTicketsCost(excursion);
    final revenue = _resolveAdminRevenue(excursion);
    final actualAmount = excursion.actualAmount;
    final total = revenue - transportCost - guideCost - entryTicketsCost;
    final transportDetails = _resolveAdminTransportDetails(excursion);
    final guideDetails = _resolveAdminGuideDetails(excursion);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stops.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Text('Остановки будут показаны после бронирований.'),
          )
        else
          ...stops.map((stop) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flag, size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          stop.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${stop.seats.length} мест',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...stop.sellers.map((seller) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: _parseAdminManifestColor(seller.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  seller.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Места: ${seller.seats.map((seat) => seat.seatNumber).join(', ')}',
                                  style: TextStyle(color: Colors.grey.shade800),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AdminManifestFinanceRow(
                label: 'Транспорт',
                subtitle: transportDetails,
                value: '${transportCost.toStringAsFixed(0)} ₽',
              ),
              const SizedBox(height: 6),
              _AdminManifestFinanceRow(
                label: 'Экскурсовод',
                subtitle: guideDetails,
                value: '${guideCost.toStringAsFixed(0)} ₽',
              ),
              const SizedBox(height: 6),
              _AdminManifestFinanceRow(
                label: 'Входные билеты',
                value: '${entryTicketsCost.toStringAsFixed(0)} ₽',
              ),
              const SizedBox(height: 12),
              _AdminManifestFinanceRow(
                label: 'Свободные места',
                value: '${excursion.availableSeatsCount}',
              ),
              const SizedBox(height: 6),
              _AdminManifestFinanceRow(
                label: 'Фактическая сумма',
                value: actualAmount != null
                    ? '${actualAmount.toStringAsFixed(0)} ₽'
                    : '—',
                valueColor: Colors.blueGrey.shade700,
                trailingIcon: Icons.edit_outlined,
                onTap: onEditActualAmount,
              ),
              const SizedBox(height: 10),
              _AdminManifestFinanceRow(
                label: 'Итого',
                value: '${total.toStringAsFixed(0)} ₽',
                isHighlighted: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminManifestFinanceRow extends StatelessWidget {
  const _AdminManifestFinanceRow({
    required this.label,
    this.subtitle,
    required this.value,
    this.valueColor,
    this.isHighlighted = false,
    this.onTap,
    this.trailingIcon,
  });

  final String label;
  final String? subtitle;
  final String value;
  final Color? valueColor;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: isHighlighted
                    ? TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green.shade800,
                      )
                    : null,
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(
            trailingIcon,
            size: 18,
            color: Colors.blueGrey.shade600,
          ),
        ],
        const SizedBox(width: 8),
        Flexible(
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              textAlign: TextAlign.right,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: isHighlighted
                  ? TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green.shade800,
                    )
                  : TextStyle(
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
            ),
          ),
        ),
      ],
    );
    if (onTap == null) {
      return row;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: row,
      ),
    );
  }
}

class _AdminActualAmountDialogResult {
  const _AdminActualAmountDialogResult(this.value);

  final double? value;
}

Future<_AdminActualAmountDialogResult?> _showAdminActualAmountDialog(
  BuildContext context, {
  required double? initialAmount,
}) async {
  final controller = TextEditingController(
    text: initialAmount != null ? initialAmount.toStringAsFixed(0) : '',
  );

  return showDialog<_AdminActualAmountDialogResult?>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Фактическая сумма'),
      content: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'Сумма',
          hintText: 'Введите фактическую сумму',
          suffixText: '₽',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(
            const _AdminActualAmountDialogResult(null),
          ),
          child: const Text('Сбросить'),
        ),
        FilledButton(
          onPressed: () {
            final normalized = controller.text.trim().replaceAll(',', '.');
            final parsed = double.tryParse(normalized);
            if (parsed == null || parsed < 0) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('Введите корректную неотрицательную сумму'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            Navigator.of(dialogContext).pop(
              _AdminActualAmountDialogResult(parsed),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
}

class _AdminManifestStopGroup {
  const _AdminManifestStopGroup({
    required this.title,
    required this.order,
    required this.seats,
    required this.sellers,
  });

  final String title;
  final int order;
  final List<BusSeat> seats;
  final List<_AdminManifestSellerGroup> sellers;
}

class _AdminManifestSellerGroup {
  const _AdminManifestSellerGroup({
    required this.name,
    required this.color,
    required this.seats,
  });

  final String name;
  final String? color;
  final List<BusSeat> seats;
}

String _resolveAdminTransportDetails(Excursion excursion) {
  final labels = _filterManifestBusAssignments(excursion)
      .map((assignment) {
        final bus = assignment.bus;
        if (bus == null) {
          return '';
        }

        final parts = <String>[];
        if (bus.model?.trim().isNotEmpty == true) {
          parts.add(bus.model!.trim());
        }
        if (bus.number.trim().isNotEmpty) {
          parts.add('№${bus.number.trim()}');
        }
        if (parts.isEmpty && bus.licensePlate?.trim().isNotEmpty == true) {
          parts.add(bus.licensePlate!.trim());
        }

        return parts.join(' ');
      })
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  if (labels.isEmpty) {
    return 'не назначен';
  }

  return labels.join(', ');
}

String _resolveAdminGuideDetails(Excursion excursion) {
  final labels = _manifestGuidesForSlot(excursion)
      .map((staff) => staff.name.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  if (labels.isEmpty) {
    return 'не назначен';
  }

  return labels.join(', ');
}

List<_AdminManifestStopGroup> _buildAdminManifestStops(List<BusSeat> busSeats) {
  final groupedStops = <String, List<BusSeat>>{};
  for (final seat in busSeats) {
    final stopTitle = seat.booking?.stopTitle?.trim() ?? '';
    if (stopTitle.isEmpty) {
      continue;
    }
    groupedStops.putIfAbsent(stopTitle, () => []).add(seat);
  }

  final result = <_AdminManifestStopGroup>[];
  for (final entry in groupedStops.entries) {
    final seats = [...entry.value]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    int stopOrder = 9999;
    for (final seat in seats) {
      final order = seat.booking?.stopOrder;
      if (order != null && order < stopOrder) {
        stopOrder = order;
      }
    }

    final sellersMap = <String, List<BusSeat>>{};
    for (final seat in seats) {
      final sellerName = (seat.bookedByInfo?.name.trim().isNotEmpty ?? false)
          ? seat.bookedByInfo!.name.trim()
          : 'Без продавца';
      sellersMap.putIfAbsent(sellerName, () => []).add(seat);
    }

    final sellers = <_AdminManifestSellerGroup>[];
    for (final sellerEntry in sellersMap.entries) {
      final sellerSeats = [...sellerEntry.value]
        ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
      sellers.add(
        _AdminManifestSellerGroup(
          name: sellerEntry.key,
          color: sellerSeats.first.bookedByInfo?.color,
          seats: sellerSeats,
        ),
      );
    }
    sellers.sort((a, b) => a.name.compareTo(b.name));

    result.add(
      _AdminManifestStopGroup(
        title: entry.key,
        order: stopOrder,
        seats: seats,
        sellers: sellers,
      ),
    );
  }

  result.sort((a, b) {
    final orderCompare = a.order.compareTo(b.order);
    if (orderCompare != 0) {
      return orderCompare;
    }
    return a.title.compareTo(b.title);
  });

  return result;
}

double _resolveAdminStaffCost(
  Excursion excursion,
  String staffType, {
  required bool isAssigned,
  ExcursionStaff? assignedStaff,
}) {
  final actualBookedSeats =
      excursion.busSeats.where((seat) => seat.booking != null).length;

  if (actualBookedSeats <= 0 || !isAssigned) {
    return 0;
  }

  if (assignedStaff?.manualAmount != null) {
    return assignedStaff!.manualAmount!;
  }

  for (final price in excursion.staffPrices) {
    if (price.staffType != staffType) {
      continue;
    }
    if (actualBookedSeats < price.minPassengers) {
      continue;
    }
    if (price.maxPassengers != null &&
        actualBookedSeats > price.maxPassengers!) {
      continue;
    }
    return price.price;
  }

  return 0;
}

double _resolveAdminRevenue(Excursion excursion) {
  double sum = 0;
  for (final seat in excursion.busSeats) {
    final booking = seat.booking;
    if (booking == null) {
      continue;
    }
    if (booking.price != null) {
      sum += booking.price!;
      continue;
    }
    final tariff =
        excursion.tariffs[booking.passengerType] ?? excursion.tariffs['adult'];
    if (tariff == null) {
      continue;
    }
    sum += booking.withEntry
        ? (tariff.priceWithEntry ?? tariff.price)
        : (tariff.priceWithoutEntry ?? tariff.price);
  }
  return sum;
}

double _resolveAdminEntryTicketsCost(Excursion excursion) {
  double sum = 0;
  for (final seat in excursion.busSeats) {
    final booking = seat.booking;
    if (booking == null || !booking.withEntry) {
      continue;
    }
    final tariff =
        excursion.tariffs[booking.passengerType] ?? excursion.tariffs['adult'];
    if (tariff == null) {
      continue;
    }
    final diff = (tariff.priceWithEntry ?? tariff.price) -
        (tariff.priceWithoutEntry ?? tariff.price);
    if (diff > 0) {
      sum += diff;
    }
  }
  return sum;
}

Color _parseAdminManifestColor(String? color) {
  if (color == null || color.isEmpty) {
    return Colors.orange.shade200;
  }
  try {
    return Color(
      int.parse(color.replaceFirst('#', ''), radix: 16) + 0xFF000000,
    );
  } catch (_) {
    return Colors.orange.shade200;
  }
}

class _AdminManifestTicketLine {
  const _AdminManifestTicketLine({
    required this.label,
    required this.unitPrice,
    required this.count,
  });

  final String label;
  final double unitPrice;
  final int count;

  double get total => unitPrice * count;
}

class _AdminManifestVehicleSummary {
  const _AdminManifestVehicleSummary({
    required this.label,
    required this.busLabel,
    required this.guideName,
    required this.totalSeats,
    required this.bookedSeats,
    required this.freeSeats,
    required this.transportCost,
    required this.guideCost,
    required this.entryTicketsCost,
    required this.debt,
    required this.finalAmount,
    required this.ticketLines,
  });

  final String label;
  final String busLabel;
  final String guideName;
  final int totalSeats;
  final int bookedSeats;
  final int freeSeats;
  final double transportCost;
  final double guideCost;
  final double entryTicketsCost;
  final double debt;
  final double finalAmount;
  final List<_AdminManifestTicketLine> ticketLines;
}

String _manifestTargetDate(Excursion excursion) =>
    DateFormat('yyyy-MM-dd').format(excursion.dateTime);

String _manifestTargetTime(Excursion excursion) =>
    DateFormat('HH:mm').format(excursion.dateTime);

List<ExcursionStaff> _filterManifestStaffForSlot(Excursion excursion) {
  final targetDate = _manifestTargetDate(excursion);
  final targetTime = _manifestTargetTime(excursion);

  return excursion.assignedStaff.where((staff) {
    final matchesDate =
        staff.excursionDate == null || staff.excursionDate == targetDate;
    final matchesTime = staff.time == null || staff.time == targetTime;
    return matchesDate && matchesTime;
  }).toList();
}

List<ExcursionBusAssignment> _filterManifestBusAssignments(
    Excursion excursion) {
  final targetDate = _manifestTargetDate(excursion);
  final targetTime = _manifestTargetTime(excursion);

  return excursion.busAssignments.where((assignment) {
    final matchesDate = assignment.excursionDate == null ||
        assignment.excursionDate == targetDate;
    final matchesTime =
        assignment.time == null || assignment.time == targetTime;
    return matchesDate && matchesTime;
  }).toList()
    ..sort((a, b) => a.seatFrom.compareTo(b.seatFrom));
}

List<ExcursionStaff> _manifestGuidesForSlot(Excursion excursion) {
  final filteredStaff = _filterManifestStaffForSlot(excursion);
  final realGuides = filteredStaff
      .where((member) => member.roleInExcursion == 'guide')
      .toList();

  if (realGuides.isNotEmpty) {
    return realGuides;
  }

  return filteredStaff
      .where((member) => member.roleInExcursion == 'driver')
      .map((member) => member.asAutoGuideFromDriver())
      .toList();
}

double _resolveAdminStaffRate(Excursion excursion, String staffType) {
  final actualBookedSeats =
      excursion.busSeats.where((seat) => seat.booking != null).length;

  if (actualBookedSeats <= 0) {
    return 0;
  }

  for (final price in excursion.staffPrices) {
    if (price.staffType != staffType) {
      continue;
    }
    if (actualBookedSeats < price.minPassengers) {
      continue;
    }
    if (price.maxPassengers != null &&
        actualBookedSeats > price.maxPassengers!) {
      continue;
    }
    return price.price;
  }

  return 0;
}

double _resolveAdminSeatEntryAmount(Excursion excursion, BusSeat seat) {
  final booking = seat.booking;
  if (booking == null || !booking.withEntry) {
    return 0;
  }

  final tariff =
      excursion.tariffs[booking.passengerType] ?? excursion.tariffs['adult'];
  if (tariff == null) {
    return 0;
  }

  final diff = (tariff.priceWithEntry ?? tariff.price) -
      (tariff.priceWithoutEntry ?? tariff.price);
  return diff > 0 ? diff : 0;
}

String _manifestPassengerShortLabel(String passengerType) {
  switch (passengerType) {
    case 'adult':
      return 'Взр.';
    case 'senior':
      return 'Пенс.';
    case 'child':
      return 'Дет.';
    case 'disabled':
      return 'Инв.';
    case 'special':
      return 'Спец.';
    case 'concession':
      return 'Льгот.';
    default:
      return passengerType.isEmpty ? 'Проч.' : passengerType;
  }
}

String _manifestFormatMoney(double value) => value.toStringAsFixed(0);

String _manifestFormatMoneyRub(double value) =>
    '${_manifestFormatMoney(value)} р';

List<_AdminManifestTicketLine> _buildManifestTicketLines(
  Excursion excursion,
  List<BusSeat> seats,
) {
  const baseOrder = ['adult', 'senior', 'child', 'disabled'];
  final extraTypes = <String>{};
  final lines = <_AdminManifestTicketLine>[];

  for (final type in baseOrder) {
    final typeSeats = seats.where((seat) {
      final booking = seat.booking;
      return booking != null &&
          booking.withEntry &&
          booking.passengerType == type;
    }).toList();

    final unitPrice = typeSeats.isEmpty
        ? 0.0
        : _resolveAdminSeatEntryAmount(excursion, typeSeats.first);

    lines.add(
      _AdminManifestTicketLine(
        label: _manifestPassengerShortLabel(type),
        unitPrice: unitPrice,
        count: typeSeats.length,
      ),
    );
  }

  for (final seat in seats) {
    final booking = seat.booking;
    if (booking == null || !booking.withEntry) {
      continue;
    }
    if (!baseOrder.contains(booking.passengerType)) {
      extraTypes.add(booking.passengerType);
    }
  }

  final sortedExtraTypes = extraTypes.toList()..sort();
  for (final type in sortedExtraTypes) {
    final typeSeats = seats.where((seat) {
      final booking = seat.booking;
      return booking != null &&
          booking.withEntry &&
          booking.passengerType == type;
    }).toList();
    if (typeSeats.isEmpty) {
      continue;
    }

    lines.add(
      _AdminManifestTicketLine(
        label: _manifestPassengerShortLabel(type),
        unitPrice: _resolveAdminSeatEntryAmount(excursion, typeSeats.first),
        count: typeSeats.length,
      ),
    );
  }

  return lines;
}

List<_AdminManifestVehicleSummary> _buildManifestVehicleSummaries(
  Excursion excursion,
) {
  final assignments = _filterManifestBusAssignments(excursion);
  final guides = _manifestGuidesForSlot(excursion);
  final driverRate = _resolveAdminStaffRate(excursion, 'driver');
  final guideRate = _resolveAdminStaffRate(excursion, 'guide');
  final sortedSeats = [...excursion.busSeats]
    ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

  if (assignments.isEmpty) {
    final bookedSeats =
        sortedSeats.where((seat) => seat.booking != null).toList();
    final freeSeats = sortedSeats.where((seat) => seat.booking == null).length;
    final entryTicketsCost = bookedSeats.fold<double>(
      0,
      (sum, seat) => sum + _resolveAdminSeatEntryAmount(excursion, seat),
    );
    final debt = bookedSeats.fold<double>(
      0,
      (sum, seat) => sum + (seat.booking?.debt ?? 0),
    );
    final guideName = guides.isNotEmpty ? guides.first.name : '—';

    return [
      _AdminManifestVehicleSummary(
        label: 'Авто1',
        busLabel: '—',
        guideName: guideName,
        totalSeats: excursion.maxSeats,
        bookedSeats: bookedSeats.length,
        freeSeats: freeSeats,
        transportCost: 0,
        guideCost: guideName == '—' ? 0 : guideRate,
        entryTicketsCost: entryTicketsCost,
        debt: debt,
        finalAmount:
            entryTicketsCost + (guideName == '—' ? 0 : guideRate) - debt,
        ticketLines: _buildManifestTicketLines(excursion, bookedSeats),
      ),
    ];
  }

  final summaries = <_AdminManifestVehicleSummary>[];
  for (var index = 0; index < assignments.length; index++) {
    final assignment = assignments[index];
    final seats = sortedSeats.where((seat) {
      return seat.seatNumber >= assignment.seatFrom &&
          seat.seatNumber <= assignment.seatTo;
    }).toList();
    final bookedSeats = seats.where((seat) => seat.booking != null).toList();
    final freeSeats = seats.where((seat) => seat.booking == null).length;
    final entryTicketsCost = bookedSeats.fold<double>(
      0,
      (sum, seat) => sum + _resolveAdminSeatEntryAmount(excursion, seat),
    );
    final debt = bookedSeats.fold<double>(
      0,
      (sum, seat) => sum + (seat.booking?.debt ?? 0),
    );

    final busParts = <String>[];
    final busNumber = assignment.bus?.number.trim() ?? '';
    final busModel = assignment.bus?.model?.trim() ?? '';
    if (busNumber.isNotEmpty) {
      busParts.add(busNumber);
    }
    if (busModel.isNotEmpty) {
      busParts.add(busModel);
    }

    final busLabel = busParts.isNotEmpty ? busParts.join(' · ') : '—';
    final guideName = index < guides.length ? guides[index].name : '—';
    final hasDriver = (assignment.driver?.name.trim().isNotEmpty ?? false);
    final hasGuide = guideName.trim().isNotEmpty && guideName != '—';
    final totalSeats = assignment.allocatedSeats > 0
        ? assignment.allocatedSeats
        : assignment.seatTo - assignment.seatFrom + 1;

    summaries.add(
      _AdminManifestVehicleSummary(
        label: 'Авто${index + 1}',
        busLabel: busLabel,
        guideName: guideName,
        totalSeats: totalSeats,
        bookedSeats: bookedSeats.length,
        freeSeats: freeSeats,
        transportCost: hasDriver ? driverRate : 0,
        guideCost: hasGuide ? guideRate : 0,
        entryTicketsCost: entryTicketsCost,
        debt: debt,
        finalAmount: (hasDriver ? driverRate : 0) +
            (hasGuide ? guideRate : 0) +
            entryTicketsCost -
            debt,
        ticketLines: _buildManifestTicketLines(excursion, bookedSeats),
      ),
    );
  }

  return summaries;
}

pw.Widget _manifestPdfTextCell(
  String text,
  pw.TextStyle style, {
  pw.TextAlign textAlign = pw.TextAlign.left,
  pw.Alignment alignment = pw.Alignment.centerLeft,
  double padding = 6,
  int? minLines,
}) {
  final lines = text.isEmpty ? [''] : text.split('\n');
  final lineCount =
      minLines != null && lines.length < minLines ? minLines : lines.length;

  return pw.Container(
    alignment: alignment,
    padding: pw.EdgeInsets.all(padding),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: List<pw.Widget>.generate(lineCount, (index) {
        return pw.Text(
          index < lines.length ? lines[index] : '',
          style: style,
          textAlign: textAlign,
        );
      }),
    ),
  );
}

pw.TableRow _manifestPdfSimpleRow(
  List<pw.Widget> children, {
  bool isHeader = false,
}) {
  return pw.TableRow(
    decoration:
        isHeader ? const pw.BoxDecoration(color: PdfColors.grey200) : null,
    children: children,
  );
}

Future<Uint8List> _buildManifestPdfBytes({
  required Excursion excursion,
  required DateFormat formatter,
  required bool hasDriverAssigned,
  required bool hasGuideAssigned,
}) async {
  final actualAmount = excursion.actualAmount;
  final vehicleSummaries = _buildManifestVehicleSummaries(excursion);
  final visibleColumnCount =
      vehicleSummaries.length < 4 ? 4 : vehicleSummaries.length;
  final bookedSeatsOverall =
      excursion.busSeats.where((seat) => seat.booking != null).length;
  final freeSeatsOverall = excursion.availableSeatsCount;
  final totalPassengers = vehicleSummaries.fold<int>(
    0,
    (sum, item) => sum + item.bookedSeats,
  );
  final totalTransport = vehicleSummaries.fold<double>(
    0,
    (sum, item) => sum + item.transportCost,
  );
  final totalGuides = vehicleSummaries.fold<double>(
    0,
    (sum, item) => sum + item.guideCost,
  );
  final totalEntry = vehicleSummaries.fold<double>(
    0,
    (sum, item) => sum + item.entryTicketsCost,
  );
  final totalDebt = vehicleSummaries.fold<double>(
    0,
    (sum, item) => sum + item.debt,
  );
  final totalFinal = vehicleSummaries.fold<double>(
    0,
    (sum, item) => sum + item.finalAmount,
  );
  final totalChange = actualAmount != null ? actualAmount - totalFinal : null;

  final pdf = pw.Document();
  final baseStyle = await TicketGenerator.textStyle(fontSize: 9);
  final titleStyle = await TicketGenerator.textStyle(
    fontSize: 18,
    fontWeight: pw.FontWeight.bold,
  );
  final sectionStyle = await TicketGenerator.textStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
  );
  final strongStyle = await TicketGenerator.textStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
  );
  final totalStyle = await TicketGenerator.textStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
  );

  List<String> vehicleCellText(
    String Function(_AdminManifestVehicleSummary item) builder,
  ) {
    return List<String>.generate(visibleColumnCount, (index) {
      if (index >= vehicleSummaries.length) {
        return '';
      }
      return builder(vehicleSummaries[index]);
    });
  }

  final summaryColumnWidths = <int, pw.TableColumnWidth>{
    0: const pw.FlexColumnWidth(1.55),
    for (var i = 1; i <= visibleColumnCount; i++)
      i: const pw.FlexColumnWidth(1),
    visibleColumnCount + 1: const pw.FlexColumnWidth(1.05),
  };

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          '${formatter.format(excursion.dateTime)} — ${excursion.title}',
          style: titleStyle,
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Мест: $bookedSeatsOverall/${excursion.maxSeats}',
          style: baseStyle,
        ),
        pw.SizedBox(height: 16),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          children: [
            _manifestPdfSimpleRow([
              _manifestPdfTextCell(
                'Авто1: ${vehicleSummaries.isNotEmpty ? vehicleSummaries[0].busLabel : ''}',
                strongStyle,
              ),
              _manifestPdfTextCell(
                'Экскурсовод 1: ${vehicleSummaries.isNotEmpty ? vehicleSummaries[0].guideName : ''}',
                strongStyle,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell(
                'Авто2: ${vehicleSummaries.length > 1 ? vehicleSummaries[1].busLabel : ''}',
                strongStyle,
              ),
              _manifestPdfTextCell(
                'Экскурсовод 2: ${vehicleSummaries.length > 1 ? vehicleSummaries[1].guideName : ''}',
                strongStyle,
              ),
            ]),
            if (vehicleSummaries.length > 2)
              ...List<pw.TableRow>.generate(
                vehicleSummaries.length - 2,
                (offset) {
                  final index = offset + 2;
                  final item = vehicleSummaries[index];
                  return _manifestPdfSimpleRow([
                    _manifestPdfTextCell(
                      'Авто${index + 1}: ${item.busLabel}',
                      strongStyle,
                    ),
                    _manifestPdfTextCell(
                      'Экскурсовод ${index + 1}: ${item.guideName}',
                      strongStyle,
                    ),
                  ]);
                },
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          children: [
            _manifestPdfSimpleRow([
              _manifestPdfTextCell(
                'Кол-во чел общ: $totalPassengers',
                strongStyle,
              ),
              _manifestPdfTextCell('Св. места: $freeSeatsOverall', strongStyle),
              ...List<pw.Widget>.generate(visibleColumnCount, (index) {
                if (index >= vehicleSummaries.length) {
                  return _manifestPdfTextCell('', baseStyle);
                }
                final item = vehicleSummaries[index];
                return _manifestPdfTextCell(
                  '${item.label}: ${item.bookedSeats} чел, св. места: ${item.freeSeats}',
                  baseStyle,
                );
              }),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          columnWidths: summaryColumnWidths,
          children: [
            _manifestPdfSimpleRow(
              [
                _manifestPdfTextCell('', strongStyle),
                ...List<pw.Widget>.generate(
                  visibleColumnCount,
                  (index) => _manifestPdfTextCell(
                    'Авто${index + 1}',
                    strongStyle,
                    textAlign: pw.TextAlign.center,
                    alignment: pw.Alignment.center,
                  ),
                ),
                _manifestPdfTextCell(
                  'Итог',
                  strongStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ],
              isHeader: true,
            ),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Транспорт', baseStyle),
              ...vehicleCellText(
                  (item) => _manifestFormatMoney(item.transportCost)).map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                _manifestFormatMoneyRub(totalTransport),
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Экскурсовод', baseStyle),
              ...vehicleCellText((item) => _manifestFormatMoney(item.guideCost))
                  .map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                _manifestFormatMoneyRub(totalGuides),
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Входные билеты', baseStyle),
              ...vehicleCellText(
                (item) => _manifestFormatMoneyRub(item.entryTicketsCost),
              ).map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                _manifestFormatMoneyRub(totalEntry),
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Кол-во чел', baseStyle),
              ...vehicleCellText((item) => '${item.bookedSeats}').map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                '$totalPassengers',
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Свободные места', baseStyle),
              ...vehicleCellText((item) => '${item.freeSeats}').map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                '$freeSeatsOverall',
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Долги', baseStyle),
              ...vehicleCellText((item) => _manifestFormatMoney(item.debt)).map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                _manifestFormatMoneyRub(totalDebt),
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Итоговая сумма', baseStyle),
              ...vehicleCellText(
                (item) => _manifestFormatMoneyRub(item.finalAmount),
              ).map(
                (value) => _manifestPdfTextCell(
                  value,
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                _manifestFormatMoneyRub(totalFinal),
                totalStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Выданная сумма', baseStyle),
              ...List<pw.Widget>.generate(
                visibleColumnCount,
                (index) => _manifestPdfTextCell(
                  '',
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                actualAmount != null
                    ? _manifestFormatMoneyRub(actualAmount)
                    : '—',
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
            _manifestPdfSimpleRow([
              _manifestPdfTextCell('Сдача', baseStyle),
              ...List<pw.Widget>.generate(
                visibleColumnCount,
                (index) => _manifestPdfTextCell(
                  '',
                  baseStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              _manifestPdfTextCell(
                totalChange != null
                    ? _manifestFormatMoneyRub(totalChange)
                    : '—',
                strongStyle,
                textAlign: pw.TextAlign.center,
                alignment: pw.Alignment.center,
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          children: [
            _manifestPdfSimpleRow(
              [
                _manifestPdfTextCell(
                  'Входные билеты',
                  sectionStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ],
              isHeader: true,
            ),
          ],
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.7),
          columnWidths: {
            for (var i = 0; i < visibleColumnCount; i++)
              i: const pw.FlexColumnWidth(1),
          },
          children: [
            _manifestPdfSimpleRow(
              List<pw.Widget>.generate(
                visibleColumnCount,
                (index) => _manifestPdfTextCell(
                  'Авто${index + 1}',
                  strongStyle,
                  textAlign: pw.TextAlign.center,
                  alignment: pw.Alignment.center,
                ),
              ),
              isHeader: true,
            ),
            _manifestPdfSimpleRow(
              List<pw.Widget>.generate(visibleColumnCount, (index) {
                if (index >= vehicleSummaries.length) {
                  return _manifestPdfTextCell('', baseStyle, minLines: 7);
                }
                final item = vehicleSummaries[index];
                final buffer = StringBuffer();
                for (final line in item.ticketLines) {
                  buffer.writeln(
                    '${line.label} ${_manifestFormatMoney(line.unitPrice)} × ${line.count} = ${_manifestFormatMoney(line.total)}',
                  );
                }
                buffer.writeln();
                buffer.write(
                  'Итого входных: ${_manifestFormatMoneyRub(item.entryTicketsCost)}',
                );
                return _manifestPdfTextCell(
                  buffer.toString(),
                  baseStyle,
                  minLines: 7,
                );
              }),
            ),
          ],
        ),
        if (!hasDriverAssigned && !hasGuideAssigned)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Примечание: для этой экскурсии не назначены водитель и экскурсовод.',
              style: baseStyle,
            ),
          )
        else if (!hasDriverAssigned || !hasGuideAssigned)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Примечание: часть данных по персоналу отсутствует, поэтому некоторые ячейки оставлены пустыми.',
              style: baseStyle,
            ),
          ),
      ],
    ),
  );

  return pdf.save();
}

class _ExcursionBusesSheet extends ConsumerStatefulWidget {
  const _ExcursionBusesSheet({
    required this.excursionId,
    required this.excursionTitle,
    required this.excursionDate,
    required this.excursionTime,
    required this.currentAssignments,
    required this.availableBuses,
  });

  final int excursionId;
  final String excursionTitle;
  final String excursionDate;
  final String excursionTime;
  final List<ExcursionBusAssignment> currentAssignments;
  final List<Bus> availableBuses;

  @override
  ConsumerState<_ExcursionBusesSheet> createState() =>
      _ExcursionBusesSheetState();
}

class _ExcursionBusesSheetState extends ConsumerState<_ExcursionBusesSheet> {
  int? _selectedBusId;
  int? _selectedDriverId;
  bool _submitting = false;

  Bus? get _selectedBus {
    if (_selectedBusId == null) return null;
    for (final bus in widget.availableBuses) {
      if (bus.id == _selectedBusId) return bus;
    }
    return null;
  }

  List<Bus> get _assignableBuses {
    final assignedBusIds =
        widget.currentAssignments.map((e) => e.busId).toSet();
    return widget.availableBuses
        .where((bus) => !assignedBusIds.contains(bus.id))
        .where((bus) => (bus.drivers?.isNotEmpty ?? false))
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));
  }

  Future<void> _assignBus() async {
    final bus = _selectedBus;
    final driverId = _selectedDriverId;
    if (bus == null || driverId == null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(busesRepositoryProvider).assignToExcursion(
            busId: bus.id,
            excursionId: widget.excursionId,
            driverId: driverId,
            excursionDate: widget.excursionDate,
            time: widget.excursionTime,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Автобус назначен на эту дату'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось назначить автобус: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _unassignBus(ExcursionBusAssignment assignment) async {
    setState(() => _submitting = true);
    try {
      await ref.read(busesRepositoryProvider).unassignFromExcursion(
            busId: assignment.busId,
            excursionId: widget.excursionId,
            excursionDate: widget.excursionDate,
            time: widget.excursionTime,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Автобус снят с этой даты'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Не удалось снять автобус: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, controller) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Автобусы — ${widget.excursionTitle}',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Дата: ${widget.excursionDate} · ${widget.excursionTime}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              const Divider(height: 24),
              Expanded(
                child: widget.currentAssignments.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.directions_bus_outlined,
                                size: 48,
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Автобусы на эту дату не назначены',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ниже можно назначить автобус и выделить ему следующий свободный диапазон мест.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: widget.currentAssignments.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, index) {
                          final assignment = widget.currentAssignments[index];
                          final bus = assignment.bus;
                          final driverName =
                              assignment.driver?.name ?? 'Водитель не указан';
                          return Card(
                            margin: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.directions_bus,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bus == null
                                              ? 'Автобус #${assignment.busId}'
                                              : '№${bus.number}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                        if (bus?.model != null) ...[
                                          const SizedBox(height: 2),
                                          Text(bus!.model!,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        ],
                                        if (bus?.licensePlate != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            bus!.licensePlate!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.people_outline,
                                                size: 14,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Места: ${assignment.seatFrom}-${assignment.seatTo}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Водитель: $driverName',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Выделено мест: ${assignment.allocatedSeats}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: _submitting
                                        ? null
                                        : () => _unassignBus(assignment),
                                    tooltip: 'Снять автобус',
                                    icon: const Icon(Icons.close),
                                    color: Colors.red,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Назначить автобус на эту дату',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedBusId,
                      decoration: const InputDecoration(
                        labelText: 'Автобус',
                        border: OutlineInputBorder(),
                      ),
                      items: _assignableBuses
                          .map(
                            (bus) => DropdownMenuItem<int>(
                              value: bus.id,
                              child: Text(
                                '№${bus.number}${bus.model != null ? " · ${bus.model}" : ""} · ${bus.capacity} мест',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              setState(() {
                                _selectedBusId = value;
                                final drivers =
                                    _selectedBus?.drivers ?? const [];
                                _selectedDriverId = drivers.length == 1
                                    ? drivers.first.id
                                    : null;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _selectedDriverId,
                      decoration: const InputDecoration(
                        labelText: 'Водитель',
                        border: OutlineInputBorder(),
                      ),
                      items: ((_selectedBus?.drivers) ?? const [])
                          .map(
                            (driver) => DropdownMenuItem<int>(
                              value: driver.id,
                              child: Text(driver.name),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting || _selectedBus == null
                          ? null
                          : (value) =>
                              setState(() => _selectedDriverId = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _assignableBuses.isEmpty
                          ? 'Нет свободных автобусов с привязанными водителями.'
                          : 'Система сама выделит следующую свободную группу мест для выбранного автобуса.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submitting ||
                                _selectedBusId == null ||
                                _selectedDriverId == null
                            ? null
                            : _assignBus,
                        icon: _submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add),
                        label: const Text('Назначить автобус'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _AdminSeatingChartSheet extends ConsumerWidget {
  const _AdminSeatingChartSheet({
    required this.excursionId,
    required this.excursionDate,
  });

  final int excursionId;
  final DateTime excursionDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Используем данные из списка экскурсий для конкретной даты/времени
    // чтобы получить правильно пересчитанные места для этой даты
    final excursionsAsync = ref.watch(excursionsFutureProvider);
    final targetDate = DateFormat('yyyy-MM-dd').format(excursionDate);
    final targetTime = DateFormat('HH:mm').format(excursionDate);

    final excursionAsync = excursionsAsync.when(
      data: (excursions) {
        // Ищем экскурсию с нужным ID и датой/временем
        try {
          final found = excursions.firstWhere(
            (e) {
              if (e.id != excursionId) return false;
              final eDate = DateFormat('yyyy-MM-dd').format(e.dateTime);
              final eTime = DateFormat('HH:mm').format(e.dateTime);
              return eDate == targetDate && eTime == targetTime;
            },
          );
          return AsyncValue.data(found);
        } catch (e) {
          // Если не найдена для конкретной даты, используем первую с таким ID
          try {
            final found = excursions.firstWhere(
              (e) => e.id == excursionId,
            );
            return AsyncValue.data(found);
          } catch (e2) {
            return AsyncValue.error(e2, StackTrace.current);
          }
        }
      },
      loading: () => const AsyncValue.loading(),
      error: (error, stack) => AsyncValue.error(error, stack),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: excursionAsync.when(
                      data: (excursion) => Text(
                        'Схема рассадки: ${excursion?.title ?? 'Загрузка...'}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      loading: () => Text(
                        'Схема рассадки: Загрузка...',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      error: (_, __) => Text(
                        'Схема рассадки: Ошибка',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: excursionAsync.when(
                data: (excursion) {
                  if (excursion == null) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Экскурсия не найдена'),
                      ),
                    );
                  }
                  return SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: _AdminSeatsGrid(
                      busSeats: excursion.busSeats,
                      busAssignments: excursion.busAssignments,
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Ошибка загрузки: $error'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminSeatsGrid extends StatelessWidget {
  const _AdminSeatsGrid({
    required this.busSeats,
    this.busAssignments = const [],
  });

  final List<BusSeat> busSeats;
  final List<ExcursionBusAssignment> busAssignments;

  @override
  Widget build(BuildContext context) {
    if (busSeats.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Схема мест недоступна'),
        ),
      );
    }

    final sorted = [...busSeats]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
    final assignedSeatNumbers = <int>{
      for (final assignment in busAssignments)
        for (int seat = assignment.seatFrom; seat <= assignment.seatTo; seat++)
          seat,
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sorted.map((seat) {
        final booking = seat.booking;
        final hasBooking = booking != null;

        // Отладочная информация для занятых мест
        if (seat.status == 'booked' || hasBooking) {
          print('🔍 Место №${seat.seatNumber}:');
          print('   Статус: ${seat.status}');
          print('   bookedBy: ${seat.bookedBy}');
          print('   bookedAt: ${seat.bookedAt}');
          print(
              '   booking объект: ${booking != null ? "✅ НЕ NULL" : "❌ NULL"}');
          print('   booking тип: ${booking.runtimeType}');
          if (booking != null) {
            print('   booking.customerName: "${booking.customerName}"');
            print('   booking.customerPhone: "${booking.customerPhone}"');
            print('   booking.passengerType: "${booking.passengerType}"');
          }
          print(
              '   Продавец найден: ${seat.bookedByInfo != null ? "✅ ДА" : "❌ НЕТ"}');
          if (seat.bookedByInfo != null) {
            print('   Имя продавца: ${seat.bookedByInfo!.name}');
            print(
                '   Цвет продавца: ${seat.bookedByInfo!.color ?? "не задан"}');
            print('   ID продавца: ${seat.bookedByInfo!.id}');
          }
          print('   hasBooking: $hasBooking');
          print(
              '   Информация о клиенте найдена: ${hasBooking ? "✅ ДА" : "❌ НЕТ"}');
          if (hasBooking) {
            print('   Имя клиента: ${booking.customerName}');
            print('   Телефон клиента: ${booking.customerPhone}');
            print('   Тип пассажира: ${booking.passengerType}');
          } else {
            print('   ⚠️ ПРОБЛЕМА: Место занято, но booking = null!');
            print('   Возможные причины:');
            print('     1. API не возвращает booking для этого места');
            print('     2. Парсинг модели BusSeat не работает');
            print('     3. Данные фильтруются где-то в коде');
          }
          print('');
        }

        final label = StringBuffer()..write(seat.seatNumber);
        if (hasBooking && booking.customerName.isNotEmpty) {
          label.write(' — ${booking.customerName}');
        }

        // Добавляем информацию о продавце только если есть бронирование для этой даты
        final sellerInfo = <String>[];
        if (hasBooking && seat.bookedByInfo != null) {
          sellerInfo.add('${seat.bookedByInfo!.name}');
        }

        // Преобразуем тип пассажира на русский
        String passengerTypeText = '';
        if (hasBooking && booking.passengerType.isNotEmpty) {
          final type = booking.passengerType.toLowerCase();
          switch (type) {
            case 'adult':
              passengerTypeText = 'Взрослый';
              break;
            case 'child':
              passengerTypeText = 'Детский';
              break;
            case 'senior':
              passengerTypeText = 'Пенсионер';
              break;
            case 'disabled':
              passengerTypeText = 'Инвалид';
              break;
            case 'special':
              passengerTypeText = 'Спеццена';
              break;
            case 'concession':
              passengerTypeText = 'Льготный';
              break;
            default:
              passengerTypeText = booking.passengerType;
          }
        }

        final subtitle = hasBooking
            ? [
                if (passengerTypeText.isNotEmpty) passengerTypeText,
                if (booking.stopTitle?.isNotEmpty ?? false) booking.stopTitle!,
                if ((booking.debt ?? 0) > 0)
                  'Долг: ${booking.debt!.toStringAsFixed(2)} ₽',
                // Имя продавца и телефон клиента рядом
                if (sellerInfo.isNotEmpty && booking.customerPhone.isNotEmpty)
                  '${sellerInfo.first} • ${booking.customerPhone}'
                else if (sellerInfo.isNotEmpty)
                  sellerInfo.first
                else if (booking.customerPhone.isNotEmpty)
                  booking.customerPhone,
              ].where((e) => e.isNotEmpty).join('\n')
            : (seat.status == 'available'
                ? 'Свободно'
                : (seat.bookedByInfo?.name.isNotEmpty ?? false
                    ? seat.bookedByInfo!.name
                    : 'Занято'));

        // Используем цвет продавца если место занято и есть информация о продавце с цветом
        // Цвет показываем если: есть booking ИЛИ (status == 'booked' И есть bookedByInfo с цветом)
        Color seatColor;
        final hasBookedByInfoWithColor = seat.bookedByInfo?.color != null &&
            seat.bookedByInfo!.color!.isNotEmpty;

        if ((hasBooking || seat.status == 'booked') &&
            hasBookedByInfoWithColor) {
          // Есть бронирование или место занято - показываем цвет продавца
          try {
            final hexColor = seat.bookedByInfo!.color!;
            seatColor =
                Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
          } catch (e) {
            // Если ошибка парсинга цвета, используем стандартные цвета
            seatColor = Colors.blue.shade100;
          }
        } else {
          // Нет информации о продавце или место свободно - используем стандартные цвета
          seatColor = seat.status == 'available'
              ? Colors.green.shade100
              : Colors.red.shade100;
        }
        final isAssignedToBus = assignedSeatNumbers.contains(seat.seatNumber);

        return Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: seatColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isAssignedToBus ? Colors.indigo : Colors.grey.shade300,
              width: isAssignedToBus ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AdminWalletTab extends ConsumerStatefulWidget {
  const _AdminWalletTab({required this.user});

  final User user;

  @override
  ConsumerState<_AdminWalletTab> createState() => _AdminWalletTabState();
}

class _AdminWalletTabState extends ConsumerState<_AdminWalletTab> {
  int _sectionIndex = 0;
  DateTime? _selectedDateFrom; // Дата начала диапазона
  DateTime? _selectedDateTo; // Дата конца диапазона
  final Set<DateTime> _expandedDates = {}; // Отслеживаем раскрытые даты

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return 'Сегодня';
    } else if (dateOnly == yesterday) {
      return 'Вчера';
    } else {
      return DateFormat('d MMMM yyyy', 'ru_RU').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(userWalletFutureProvider(widget.user.id));
    final salesAsync = ref.watch(userSalesFutureProvider(widget.user.id));
    final profitAsync = ref.watch(userProfitFutureProvider(widget.user.id));
    final bookingsAsync = ref.watch(bookingsFutureProvider);
    final formatter = DateFormat('dd.MM.yyyy HH:mm');

    return walletAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Ошибка: $error')),
      data: (wallet) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(userWalletFutureProvider(widget.user.id));
            ref.invalidate(userSalesFutureProvider(widget.user.id));
            ref.invalidate(userProfitFutureProvider(widget.user.id));
            ref.invalidate(bookingsFutureProvider);
            await Future.wait([
              ref.read(userWalletFutureProvider(widget.user.id).future),
              ref.read(userSalesFutureProvider(widget.user.id).future),
              ref.read(userProfitFutureProvider(widget.user.id).future),
              ref.read(bookingsFutureProvider.future),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  title: const Text('Баланс'),
                  subtitle: const Text('Текущий остаток по кошельку'),
                  trailing: Text(
                    '${wallet.balance.toStringAsFixed(2)} ₽',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.green),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'История транзакций',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  // Фильтр по диапазону дат
                  Row(
                    children: [
                      if (_selectedDateFrom != null || _selectedDateTo != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Очистить фильтр',
                          onPressed: () {
                            setState(() {
                              _selectedDateFrom = null;
                              _selectedDateTo = null;
                            });
                          },
                        ),
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final firstDate = DateTime(now.year - 1, 1, 1);
                          final lastDate = _selectedDateTo ??
                              DateTime(now.year, now.month, now.day);

                          final picked = await showDatePicker(
                            context: context,
                            firstDate: firstDate,
                            lastDate: lastDate,
                            initialDate: _selectedDateFrom ??
                                DateTime(now.year, now.month, now.day),
                          );

                          if (picked != null && mounted) {
                            setState(() {
                              _selectedDateFrom = picked;
                              // Если дата "от" больше даты "до", сбрасываем "до"
                              if (_selectedDateTo != null &&
                                  _selectedDateFrom!
                                      .isAfter(_selectedDateTo!)) {
                                _selectedDateTo = null;
                              }
                            });
                          }
                        },
                        child: Text(
                          _selectedDateFrom == null
                              ? 'ОТ'
                              : DateFormat('dd.MM.yyyy', 'ru_RU')
                                  .format(_selectedDateFrom!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final now = DateTime.now();
                          final firstDate =
                              _selectedDateFrom ?? DateTime(now.year - 1, 1, 1);
                          final lastDate =
                              DateTime(now.year, now.month, now.day);

                          final picked = await showDatePicker(
                            context: context,
                            firstDate: firstDate,
                            lastDate: lastDate,
                            initialDate: _selectedDateTo ??
                                (_selectedDateFrom ??
                                    DateTime(now.year, now.month, now.day)),
                          );

                          if (picked != null && mounted) {
                            setState(() {
                              _selectedDateTo = picked;
                              // Если дата "до" меньше даты "от", сбрасываем "от"
                              if (_selectedDateFrom != null &&
                                  _selectedDateTo!
                                      .isBefore(_selectedDateFrom!)) {
                                _selectedDateFrom = null;
                              }
                            });
                          }
                        },
                        child: Text(
                          _selectedDateTo == null
                              ? 'ДО'
                              : DateFormat('dd.MM.yyyy', 'ru_RU')
                                  .format(_selectedDateTo!),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  // Фильтруем транзакции по выбранному диапазону дат
                  var filteredTransactions = wallet.transactions;
                  if (_selectedDateFrom != null || _selectedDateTo != null) {
                    DateTime? startDate;
                    DateTime? endDate;

                    if (_selectedDateFrom != null) {
                      startDate = DateTime(
                        _selectedDateFrom!.year,
                        _selectedDateFrom!.month,
                        _selectedDateFrom!.day,
                      );
                    }

                    if (_selectedDateTo != null) {
                      endDate = DateTime(
                        _selectedDateTo!.year,
                        _selectedDateTo!.month,
                        _selectedDateTo!.day,
                        23,
                        59,
                        59,
                      );
                    }

                    filteredTransactions = wallet.transactions.where((t) {
                      // Используем дату экскурсии для фильтрации, если есть бронирование
                      DateTime transactionDate;
                      if (t.booking != null &&
                          t.booking!.excursion.dateTime != null) {
                        transactionDate = t.booking!.excursion.dateTime;
                      } else {
                        transactionDate = t.createdAt;
                      }

                      if (startDate != null &&
                          transactionDate.isBefore(
                              startDate.subtract(const Duration(seconds: 1)))) {
                        return false;
                      }
                      if (endDate != null &&
                          transactionDate.isAfter(
                              endDate.add(const Duration(seconds: 1)))) {
                        return false;
                      }
                      return true;
                    }).toList();
                  }

                  if (filteredTransactions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Транзакций нет за выбранный период'),
                    );
                  }

                  // Группируем транзакции по дате экскурсии (а не по дате продажи)
                  final groupedTransactions =
                      <DateTime, List<WalletTransactionItem>>{};
                  for (final transaction in filteredTransactions) {
                    // Используем дату экскурсии, если есть бронирование, иначе дату создания транзакции
                    DateTime transactionDate;
                    if (transaction.booking != null &&
                        transaction.booking!.excursion.dateTime != null) {
                      transactionDate = transaction.booking!.excursion.dateTime;
                    } else {
                      transactionDate = transaction.createdAt;
                    }

                    final date = DateTime(
                      transactionDate.year,
                      transactionDate.month,
                      transactionDate.day,
                    );
                    groupedTransactions
                        .putIfAbsent(date, () => [])
                        .add(transaction);
                  }

                  // Сортируем даты по убыванию (новые первыми)
                  final sortedDates = groupedTransactions.keys.toList()
                    ..sort((a, b) => b.compareTo(a));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: sortedDates.asMap().entries.map((dateEntry) {
                      final dateIndex = dateEntry.key;
                      final date = dateEntry.value;
                      final transactions = groupedTransactions[date]!;
                      // Сортируем транзакции внутри дня по дате экскурсии (новые первыми)
                      transactions.sort((a, b) {
                        DateTime dateA =
                            a.booking?.excursion.dateTime ?? a.createdAt;
                        DateTime dateB =
                            b.booking?.excursion.dateTime ?? b.createdAt;
                        return dateB.compareTo(dateA);
                      });
                      final isExpanded = _expandedDates.contains(date);

                      return _ExpandableCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: dateIndex % 2 == 0
                            ? Colors.grey.shade50
                            : Colors.white,
                        child: ExpansionTile(
                          initiallyExpanded: isExpanded,
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedDates.add(date);
                              } else {
                                _expandedDates.remove(date);
                              }
                            });
                          },
                          title: Text(
                            _formatDateHeader(date),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                          children: transactions.asMap().entries.map(
                            (entry) {
                              final transaction = entry.value;
                              final index = entry.key;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                color: index % 2 == 0
                                    ? Colors.grey.shade100
                                    : Colors.white,
                                child: ExpansionTile(
                                  leading: CircleAvatar(
                                    backgroundColor: transaction.amount >= 0
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    child: Icon(
                                      transaction.amount >= 0
                                          ? Icons.arrow_downward
                                          : Icons.arrow_upward,
                                      color: transaction.amount >= 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  title: Text(
                                    transaction.cleanedDescription,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  subtitle: Text(
                                    DateFormat('dd.MM.yyyy HH:mm')
                                        .format(transaction.createdAt),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  trailing: Text(
                                    '${transaction.amount.toStringAsFixed(2)} ₽',
                                    style: TextStyle(
                                      color: transaction.amount >= 0
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                    ),
                                  ),
                                  children: transaction.booking != null
                                      ? [
                                          ListTile(
                                            title: Text(
                                              'Бронирование',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Экскурсия: ${transaction.booking!.excursion.title}',
                                                ),
                                                if (transaction.booking!
                                                        .excursion.dateTime !=
                                                    null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'Дата: ${formatter.format(transaction.booking!.excursion.dateTime)}',
                                                  ),
                                                ],
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Клиент: ${transaction.booking!.customerName}',
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Сумма бронирования: ${transaction.booking!.price.toStringAsFixed(2)} ₽',
                                                ),
                                              ],
                                            ),
                                          ),
                                        ]
                                      : [],
                                ),
                              );
                            },
                          ).toList(),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 24),
              ToggleButtons(
                borderRadius: BorderRadius.circular(8),
                isSelected: List.generate(2, (index) => index == _sectionIndex),
                onPressed: (index) => setState(() => _sectionIndex = index),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Продажи'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Прибыль'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_sectionIndex == 0) ...[
                Text(
                  'Продажи',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                salesAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Ошибка загрузки: $error'),
                  ),
                  data: (sales) {
                    // Фильтруем продажи по выбранному диапазону дат
                    var filteredBookings = sales.bookings;
                    if (_selectedDateFrom != null || _selectedDateTo != null) {
                      DateTime? startDate;
                      DateTime? endDate;

                      if (_selectedDateFrom != null) {
                        startDate = DateTime(
                          _selectedDateFrom!.year,
                          _selectedDateFrom!.month,
                          _selectedDateFrom!.day,
                        );
                      }

                      if (_selectedDateTo != null) {
                        endDate = DateTime(
                          _selectedDateTo!.year,
                          _selectedDateTo!.month,
                          _selectedDateTo!.day,
                          23,
                          59,
                          59,
                        );
                      }

                      filteredBookings = sales.bookings.where((b) {
                        if (startDate != null &&
                            b.bookedAt.isBefore(startDate
                                .subtract(const Duration(seconds: 1)))) {
                          return false;
                        }
                        if (endDate != null &&
                            b.bookedAt.isAfter(
                                endDate.add(const Duration(seconds: 1)))) {
                          return false;
                        }
                        return true;
                      }).toList();
                    }

                    if (filteredBookings.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          (_selectedDateFrom == null && _selectedDateTo == null)
                              ? 'Продаж пока нет'
                              : 'Продаж нет за выбранный период',
                        ),
                      );
                    }

                    // Пересчитываем общую сумму продаж
                    final totalSales = filteredBookings.fold<double>(
                        0, (sum, booking) => sum + booking.price);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_selectedDateFrom != null ||
                            _selectedDateTo != null)
                          Card(
                            child: ListTile(
                              title: const Text('Общая сумма продаж'),
                              trailing: Text(
                                '${totalSales.toStringAsFixed(2)} ₽',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(color: Colors.green),
                              ),
                            ),
                          ),
                        ...filteredBookings
                            .map(
                              (booking) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ExpansionTile(
                                  title: Text(
                                    booking.excursion.title,
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formatter
                                            .format(booking.excursion.dateTime),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      Text(
                                        'Продажа: ${formatter.format(booking.bookedAt)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Colors.grey,
                                            ),
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    '${booking.price.toStringAsFixed(2)} ₽',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.green),
                                  ),
                                  children: [
                                    ListTile(
                                      title: Text(booking.excursion.title),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 8),
                                          Text(
                                            'Дата экскурсии: ${formatter.format(booking.excursion.dateTime)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Дата продажи: ${formatter.format(booking.bookedAt)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${booking.customerName} • ${booking.customerPhone}',
                                          ),
                                          const SizedBox(height: 4),
                                          Text(booking.passengerType.label),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ],
                    );
                  },
                ),
              ] else ...[
                Text(
                  'Прибыль',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                profitAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (error, _) => Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Ошибка загрузки: $error'),
                  ),
                  data: (profit) {
                    // Фильтруем прибыль по выбранному диапазону дат
                    var filteredBreakdown = profit.breakdown;
                    if (_selectedDateFrom != null || _selectedDateTo != null) {
                      DateTime? startDate;
                      DateTime? endDate;

                      if (_selectedDateFrom != null) {
                        startDate = DateTime(
                          _selectedDateFrom!.year,
                          _selectedDateFrom!.month,
                          _selectedDateFrom!.day,
                        );
                      }

                      if (_selectedDateTo != null) {
                        endDate = DateTime(
                          _selectedDateTo!.year,
                          _selectedDateTo!.month,
                          _selectedDateTo!.day,
                          23,
                          59,
                          59,
                        );
                      }

                      filteredBreakdown = profit.breakdown.where((item) {
                        if (startDate != null &&
                            item.bookedAt.isBefore(startDate
                                .subtract(const Duration(seconds: 1)))) {
                          return false;
                        }
                        if (endDate != null &&
                            item.bookedAt.isAfter(
                                endDate.add(const Duration(seconds: 1)))) {
                          return false;
                        }
                        return true;
                      }).toList();
                    }

                    if (filteredBreakdown.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          (_selectedDateFrom == null && _selectedDateTo == null)
                              ? 'Прибыль пока не рассчитана'
                              : 'Прибыль не рассчитана за выбранный период',
                        ),
                      );
                    }

                    // Пересчитываем суммы для отфильтрованных данных
                    final filteredTotalsByType =
                        <String, ({double sales, double commission})>{};
                    double filteredTotalProfit = 0;

                    for (final item in filteredBreakdown) {
                      final typeKey = item.passengerType.label;
                      final current = filteredTotalsByType[typeKey] ??
                          (sales: 0, commission: 0);
                      filteredTotalsByType[typeKey] = (
                        sales: current.sales + item.price,
                        commission: current.commission + item.commissionAmount,
                      );
                      filteredTotalProfit += item.commissionAmount;
                    }

                    final totalsTiles = filteredTotalsByType.entries
                        .map(
                          (entry) => ListTile(
                            title: Text(entry.key),
                            subtitle: Text(
                              'Продажи: ${entry.value.sales.toStringAsFixed(2)} ₽',
                            ),
                            trailing: Text(
                              '+${entry.value.commission.toStringAsFixed(2)} ₽',
                              style: const TextStyle(color: Colors.green),
                            ),
                          ),
                        )
                        .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          child: ListTile(
                            title: Text(
                              (_selectedDateFrom == null &&
                                      _selectedDateTo == null)
                                  ? 'Общая прибыль'
                                  : 'Прибыль за период',
                            ),
                            subtitle: Text(
                              profit.isPartner
                                  ? 'Партнёрская комиссия'
                                  : '10% от продаж',
                            ),
                            trailing: Text(
                              '${filteredTotalProfit.toStringAsFixed(2)} ₽',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.green),
                            ),
                          ),
                        ),
                        if (totalsTiles.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Column(
                              children: [
                                const ListTile(
                                  title: Text('Итого по категориям'),
                                ),
                                const Divider(height: 1),
                                ...totalsTiles,
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        ...profit.breakdown.map(
                          (item) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(item.excursion.title),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    formatter.format(item.excursion.dateTime),
                                  ),
                                  Text(item.passengerType.label),
                                  Text(
                                    'Продажа: ${item.price.toStringAsFixed(2)} ₽',
                                  ),
                                ],
                              ),
                              trailing: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '+${item.commissionAmount.toStringAsFixed(2)} ₽',
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${item.commissionPercent.toStringAsFixed(1)} %',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Активные бронирования',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              bookingsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Ошибка: $error'),
                ),
                data: (groups) {
                  if (groups.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Нет активных бронирований'),
                    );
                  }
                  return Column(
                    children: groups.map((group) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          title: Text(group.excursion.title),
                          subtitle: Text(
                            '${formatter.format(group.excursion.dateTime)} • ${group.bookings.length} мест',
                          ),
                          children: group.bookings
                              .map(
                                (booking) => ListTile(
                                  title:
                                      Text('Место ${booking.seat.seatNumber}'),
                                  subtitle: Text(
                                    'Бронировано: ${formatter.format(booking.bookedAt)}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.cancel),
                                    tooltip: 'Отменить',
                                    onPressed: () => _cancelBooking(
                                      context,
                                      booking.id,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelBooking(
    BuildContext context,
    int bookingId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const CancellationReasonDialog(),
    );

    if (reason == null) {
      return;
    }

    try {
      await ref
          .read(bookingsRepositoryProvider)
          .cancelBooking(bookingId, reason: reason);
      ref.invalidate(bookingsFutureProvider);
      ref.invalidate(userWalletFutureProvider(widget.user.id));
      ref.invalidate(userSalesFutureProvider(widget.user.id));
      ref.invalidate(userProfitFutureProvider(widget.user.id));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Бронирование отменено'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось отменить: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

class _AdminScheduleTab extends ConsumerStatefulWidget {
  const _AdminScheduleTab();

  @override
  ConsumerState<_AdminScheduleTab> createState() => _AdminScheduleTabState();
}

class _AdminScheduleTabState extends ConsumerState<_AdminScheduleTab> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(scheduleFutureProvider);
    final internetStatusAsync = ref.watch(internetStatusProvider);
    final appBarColor = internetStatusAsync.when(
      data: (status) =>
          status ? Theme.of(context).colorScheme.primary : Colors.red,
      loading: () => Theme.of(context).colorScheme.primary,
      error: (_, __) => Colors.red,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        title: const Text('Расписание'),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              color: Colors.white,
              tooltip: 'Обновить',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() {
                  _isRefreshing = true;
                });
                ref.invalidate(scheduleFutureProvider);
                ref.invalidate(excursionsFutureProvider);
                // Ждем завершения обновления
                try {
                  await ref.read(scheduleFutureProvider.future);
                } catch (_) {
                  // Игнорируем ошибки при обновлении
                }
                if (mounted) {
                  setState(() {
                    _isRefreshing = false;
                  });
                }
              },
            ),
        ],
      ),
      body: scheduleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Ошибка загрузки расписания: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(scheduleFutureProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return const Center(
              child: Text('Расписание пока не настроено'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(scheduleFutureProvider);
              ref.invalidate(excursionsFutureProvider);
            },
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: templates.length,
                    itemBuilder: (context, index) {
                      final template = templates[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          leading: const Icon(Icons.calendar_today),
                          title: Text(
                            template.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: template.description.isNotEmpty
                              ? Text(
                                  template.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          children: [
                            if (template.description.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Text(
                                  template.description,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                              const Divider(),
                            ],
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Расписание по дням недели:',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  if (template.schedule.isEmpty)
                                    const Text(
                                      'Расписание не задано',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        color: Colors.grey,
                                      ),
                                    )
                                  else
                                    ...template.schedule.map((day) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 120,
                                              child: Text(
                                                day.dayName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                            ),
                                            Text(
                                              day.time,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Раздел "Внеплановые"
                Consumer(
                  builder: (context, ref, _) {
                    final excursionsAsync = ref.watch(excursionsFutureProvider);
                    return excursionsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (excursions) {
                        // Собираем все внеплановые экскурсии
                        final now = DateTime.now();
                        final unscheduledExcursions =
                            excursions.where((e) => e.isUnscheduled).toList();

                        if (unscheduledExcursions.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        // Разделяем на прошедшие, будущие и удаленные
                        final pastExcursions = unscheduledExcursions
                            .where(
                                (e) => e.dateTime.isBefore(now) && !e.isDeleted)
                            .toList();
                        final futureExcursions = unscheduledExcursions
                            .where((e) =>
                                !e.dateTime.isBefore(now) && !e.isDeleted)
                            .toList();
                        final deletedExcursions = unscheduledExcursions
                            .where((e) => e.isDeleted)
                            .toList();

                        // Группируем по экскурсиям (для будущих)
                        final groupedByTitleFuture =
                            <String, List<Excursion>>{};
                        for (final excursion in futureExcursions) {
                          if (!groupedByTitleFuture
                              .containsKey(excursion.title)) {
                            groupedByTitleFuture[excursion.title] = [];
                          }
                          groupedByTitleFuture[excursion.title]!.add(excursion);
                        }

                        // Группируем по экскурсиям (для прошедших)
                        final groupedByTitlePast = <String, List<Excursion>>{};
                        for (final excursion in pastExcursions) {
                          if (!groupedByTitlePast
                              .containsKey(excursion.title)) {
                            groupedByTitlePast[excursion.title] = [];
                          }
                          groupedByTitlePast[excursion.title]!.add(excursion);
                        }

                        return Card(
                          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          color: Colors.amber.shade50,
                          child: ExpansionTile(
                            leading: const Icon(Icons.event_busy,
                                color: Colors.amber),
                            title: const Text(
                              'Внеплановые',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                                '${futureExcursions.length} ${futureExcursions.length == 1 ? 'экскурсия' : futureExcursions.length < 5 ? 'экскурсии' : 'экскурсий'}${pastExcursions.isNotEmpty ? ' (${pastExcursions.length} прошедших)' : ''}${deletedExcursions.isNotEmpty ? ' (${deletedExcursions.length} удаленных)' : ''}'),
                            children: [
                              // Будущие экскурсии
                              if (groupedByTitleFuture.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Text(
                                    'Будущие',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ),
                                ...groupedByTitleFuture.entries.map((entry) {
                                  final title = entry.key;
                                  final dates = entry.value;
                                  dates.sort((a, b) =>
                                      a.dateTime.compareTo(b.dateTime));

                                  return ExpansionTile(
                                    title: Text(title),
                                    children: dates.map((excursion) {
                                      return ListTile(
                                        title: Text(
                                          DateFormat('dd.MM.yyyy HH:mm')
                                              .format(excursion.dateTime),
                                        ),
                                        subtitle: Text(
                                          'Занято: ${excursion.bookedSeatsCount}/${excursion.maxSeats}',
                                        ),
                                        trailing: excursion.unscheduledDateId !=
                                                null
                                            ? IconButton(
                                                icon: const Icon(Icons.delete,
                                                    color: Colors.red),
                                                onPressed: () async {
                                                  // Подтверждение удаления
                                                  final confirm =
                                                      await showDialog<bool>(
                                                    context: context,
                                                    builder: (context) =>
                                                        AlertDialog(
                                                      title: const Text(
                                                          'Удалить внеплановую дату?'),
                                                      content: Text(
                                                          'Вы уверены, что хотите удалить внеплановую дату "${excursion.title}" на ${DateFormat('dd.MM.yyyy HH:mm').format(excursion.dateTime)}?'),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      context)
                                                                  .pop(false),
                                                          child: const Text(
                                                              'Отмена'),
                                                        ),
                                                        TextButton(
                                                          onPressed: () =>
                                                              Navigator.of(
                                                                      context)
                                                                  .pop(true),
                                                          child: const Text(
                                                              'Удалить',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .red)),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                                  if (confirm == true &&
                                                      context.mounted) {
                                                    try {
                                                      await ref
                                                          .read(
                                                              excursionsRepositoryProvider)
                                                          .deleteUnscheduledDate(
                                                            excursionId:
                                                                excursion.id,
                                                            dateId: excursion
                                                                .unscheduledDateId!,
                                                          );
                                                      if (context.mounted) {
                                                        ref.invalidate(
                                                            excursionsFutureProvider);
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                                'Внеплановая дата удалена'),
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                            margin:
                                                                EdgeInsets.all(
                                                                    16),
                                                          ),
                                                        );
                                                      }
                                                    } catch (e) {
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(
                                                                context)
                                                            .showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                                'Ошибка: $e'),
                                                            behavior:
                                                                SnackBarBehavior
                                                                    .floating,
                                                            margin:
                                                                const EdgeInsets
                                                                    .all(16),
                                                          ),
                                                        );
                                                      }
                                                    }
                                                  }
                                                },
                                              )
                                            : null,
                                      );
                                    }).toList(),
                                  );
                                }),
                              ],
                              // Прошедшие экскурсии
                              if (groupedByTitlePast.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Text(
                                    'Прошедшие',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16),
                                  ),
                                ),
                                ...groupedByTitlePast.entries.map((entry) {
                                  final title = entry.key;
                                  final dates = entry.value;
                                  dates.sort((a, b) => b.dateTime.compareTo(
                                      a.dateTime)); // Сортируем по убыванию

                                  return ExpansionTile(
                                    title: Text(title),
                                    children: dates.map((excursion) {
                                      return ListTile(
                                        title: Text(
                                          DateFormat('dd.MM.yyyy HH:mm')
                                              .format(excursion.dateTime),
                                        ),
                                        subtitle: Text(
                                          'Занято: ${excursion.bookedSeatsCount}/${excursion.maxSeats}',
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }),
                              ],
                              // Удаленные экскурсии
                              if (deletedExcursions.isNotEmpty) ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Text(
                                    'Удаленные',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Colors.red),
                                  ),
                                ),
                                ...() {
                                  // Группируем по названию экскурсии
                                  final groupedByTitle =
                                      <String, List<Excursion>>{};
                                  for (final excursion in deletedExcursions) {
                                    if (!groupedByTitle
                                        .containsKey(excursion.title)) {
                                      groupedByTitle[excursion.title] = [];
                                    }
                                    groupedByTitle[excursion.title]!
                                        .add(excursion);
                                  }
                                  return groupedByTitle.entries;
                                }()
                                    .map((entry) {
                                  final title = entry.key;
                                  final dates = entry.value;
                                  dates.sort((a, b) => b.dateTime.compareTo(
                                      a.dateTime)); // Сортируем по убыванию

                                  return ExpansionTile(
                                    title: Text(title),
                                    children: dates.map((excursion) {
                                      return ListTile(
                                        title: Text(
                                          DateFormat('dd.MM.yyyy HH:mm')
                                              .format(excursion.dateTime),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Занято: ${excursion.bookedSeatsCount}/${excursion.maxSeats}',
                                          style: const TextStyle(
                                              color: Colors.grey),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                }),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CreateExcursionDialog extends ConsumerStatefulWidget {
  const _CreateExcursionDialog();

  @override
  ConsumerState<_CreateExcursionDialog> createState() =>
      _CreateExcursionDialogState();
}

class _CreateExcursionDialogState
    extends ConsumerState<_CreateExcursionDialog> {
  final _formKey = GlobalKey<FormState>();
  Excursion? _selectedExcursion;
  DateTime? _dateTime;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateTime ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime ?? now),
    );
    if (time == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _dateTime =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (_selectedExcursion == null) {
      setState(() => _errorMessage = 'Выберите экскурсию');
      return;
    }
    if (_dateTime == null) {
      setState(() => _errorMessage = 'Выберите дату и время');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final updatedExcursion =
          await ref.read(excursionsRepositoryProvider).addUnscheduledDate(
                excursionId: _selectedExcursion!.id,
                dateTime: _dateTime!,
              );
      if (mounted) {
        Navigator.of(context).pop(updatedExcursion);
      }
    } catch (error) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd.MM.yyyy HH:mm');
    final excursionsAsync = ref.watch(excursionsFutureProvider);

    return AlertDialog(
      title: const Text('Добавить внеплановую дату'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              excursionsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Text('Ошибка загрузки: $error'),
                data: (excursions) {
                  // Фильтруем уникальные экскурсии по id (убираем дубликаты от развертывания по датам)
                  final uniqueExcursions = <int, Excursion>{};
                  for (final excursion in excursions) {
                    if (!uniqueExcursions.containsKey(excursion.id)) {
                      uniqueExcursions[excursion.id] = excursion;
                    }
                  }
                  final uniqueList = uniqueExcursions.values.toList()
                    ..sort((a, b) => a.title.compareTo(b.title));

                  if (uniqueList.isEmpty) {
                    return const Text('Нет доступных экскурсий');
                  }
                  return DropdownButtonFormField<Excursion>(
                    value: _selectedExcursion,
                    decoration: const InputDecoration(
                      labelText: 'Выберите экскурсию',
                    ),
                    items: uniqueList.map((excursion) {
                      return DropdownMenuItem<Excursion>(
                        value: excursion,
                        child: Text(excursion.title),
                      );
                    }).toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) {
                            setState(() {
                              _selectedExcursion = value;
                            });
                          },
                    validator: (value) =>
                        value == null ? 'Выберите экскурсию' : null,
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Дата и время'),
                subtitle: Text(
                  _dateTime == null
                      ? 'Не выбрано'
                      : formatter.format(_dateTime!),
                ),
                trailing: TextButton(
                  onPressed: _isSubmitting ? null : _pickDateTime,
                  child: const Text('Выбрать'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Добавить'),
        ),
      ],
    );
  }
}

class _AdminStatisticsTab extends ConsumerStatefulWidget {
  const _AdminStatisticsTab();

  @override
  ConsumerState<_AdminStatisticsTab> createState() =>
      _AdminStatisticsTabState();
}

class _AdminStatisticsTabState extends ConsumerState<_AdminStatisticsTab> {
  DateTime? _selectedDateFrom;
  DateTime? _selectedDateTo;

  @override
  Widget build(BuildContext context) {
    final statisticsAsync = ref.watch(_statisticsFutureProvider);
    final formatter = DateFormat('dd.MM.yyyy HH:mm');

    return statisticsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Ошибка загрузки статистики: $error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(_statisticsFutureProvider),
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
      data: (data) {
        try {
          final statistics = (data['statistics'] as List<dynamic>?) ?? [];

          if (statistics.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_statisticsFutureProvider);
                await ref.read(_statisticsFutureProvider.future);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child:
                      const Center(child: Text('Нет данных для отображения')),
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_statisticsFutureProvider);
              await ref.read(_statisticsFutureProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Фильтр по датам
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Фильтр по датам',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today),
                                label: Text(
                                  _selectedDateFrom != null
                                      ? DateFormat('dd.MM.yyyy', 'ru_RU')
                                          .format(_selectedDateFrom!)
                                      : 'От',
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _selectedDateFrom ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _selectedDateFrom = picked;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.calendar_today),
                                label: Text(
                                  _selectedDateTo != null
                                      ? DateFormat('dd.MM.yyyy', 'ru_RU')
                                          .format(_selectedDateTo!)
                                      : 'До',
                                ),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _selectedDateTo ?? DateTime.now(),
                                    firstDate:
                                        _selectedDateFrom ?? DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _selectedDateTo = picked;
                                    });
                                  }
                                },
                              ),
                            ),
                            if (_selectedDateFrom != null ||
                                _selectedDateTo != null)
                              IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _selectedDateFrom = null;
                                    _selectedDateTo = null;
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    // Применяем фильтр по датам
                    List<dynamic> filteredStatistics = statistics;
                    if (_selectedDateFrom != null || _selectedDateTo != null) {
                      filteredStatistics = statistics.where((stat) {
                        final excursion =
                            (stat['excursion'] as Map<String, dynamic>?) ?? {};
                        final dateTimeStr = excursion['date_time'] as String?;
                        if (dateTimeStr == null || dateTimeStr.isEmpty) {
                          return false;
                        }
                        try {
                          final dateTime = DateTime.parse(dateTimeStr);
                          final dateOnly = DateTime(
                              dateTime.year, dateTime.month, dateTime.day);

                          if (_selectedDateFrom != null) {
                            final fromDate = DateTime(
                                _selectedDateFrom!.year,
                                _selectedDateFrom!.month,
                                _selectedDateFrom!.day);
                            if (dateOnly.isBefore(fromDate)) {
                              return false;
                            }
                          }
                          if (_selectedDateTo != null) {
                            final toDate = DateTime(
                                    _selectedDateTo!.year,
                                    _selectedDateTo!.month,
                                    _selectedDateTo!.day)
                                .add(const Duration(days: 1));
                            if (dateOnly.isAfter(
                                toDate.subtract(const Duration(seconds: 1)))) {
                              return false;
                            }
                          }
                          return true;
                        } catch (e) {
                          return false;
                        }
                      }).toList();
                    }

                    // Пересчитываем общую прибыль для отфильтрованных данных
                    double filteredTotalNetProfit =
                        filteredStatistics.fold<double>(
                      0.0,
                      (sum, stat) =>
                          sum +
                          ((stat['net_profit'] as num?)?.toDouble() ?? 0.0),
                    );

                    return Column(
                      children: [
                        // Карточка с общей прибылью (с учетом фильтра)
                        Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Text(
                                  'Общая чистая прибыль',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                if (_selectedDateFrom != null ||
                                    _selectedDateTo != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      _selectedDateFrom != null &&
                                              _selectedDateTo != null
                                          ? '${DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateFrom!)} - ${DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateTo!)}'
                                          : _selectedDateFrom != null
                                              ? 'С ${DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateFrom!)}'
                                              : 'До ${DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateTo!)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey.shade700,
                                          ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                Text(
                                  '${filteredTotalNetProfit.toStringAsFixed(2)} ₽',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Список статистики
                        if (filteredStatistics.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                              child: Text('Нет данных для отображения'),
                            ),
                          )
                        else
                          ...filteredStatistics.map((stat) {
                            try {
                              final excursion = (stat['excursion']
                                      as Map<String, dynamic>?) ??
                                  {};
                              final dateTimeStr =
                                  excursion['date_time'] as String?;
                              DateTime? dateTime;
                              if (dateTimeStr != null &&
                                  dateTimeStr.isNotEmpty) {
                                try {
                                  dateTime = DateTime.parse(dateTimeStr);
                                } catch (e) {
                                  // Если не удалось распарсить дату, оставляем null
                                }
                              }
                              final netProfit =
                                  ((stat['net_profit'] as num?)?.toDouble()) ??
                                      0.0;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ExpansionTile(
                                  leading: Icon(
                                    netProfit >= 0
                                        ? Icons.trending_up
                                        : Icons.trending_down,
                                    color: netProfit >= 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  title: Text(
                                    (excursion['title'] as String?) ??
                                        'Без названия',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  subtitle: Text(
                                    dateTime != null
                                        ? '${formatter.format(dateTime)} • Чистая прибыль: ${netProfit.toStringAsFixed(2)} ₽'
                                        : 'Дата не указана • Чистая прибыль: ${netProfit.toStringAsFixed(2)} ₽',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Divider(),
                                          _StatRow(
                                            label:
                                                'Доход (выручка от продажи билетов)',
                                            value:
                                                '${(((stat['income'] as num?)?.toDouble()) ?? ((stat['total_revenue'] as num?)?.toDouble()) ?? 0.0).toStringAsFixed(2)} ₽',
                                            color: Colors.blue,
                                          ),
                                          _StatRow(
                                            label: 'Продано билетов',
                                            value:
                                                '${(stat['bookings_count'] as num?)?.toInt() ?? 0} шт.',
                                            color: Colors.grey,
                                          ),
                                          const Divider(),
                                          _StatRow(
                                            label: 'Минус: Заплатили продавцам',
                                            value:
                                                '-${((stat['seller_commissions'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ₽',
                                            color: Colors.orange,
                                          ),
                                          _StatRow(
                                            label: 'Минус: Заплатили водителям',
                                            value:
                                                '-${((stat['driver_costs'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ₽',
                                            color: Colors.purple,
                                          ),
                                          _StatRow(
                                            label:
                                                'Минус: Заплатили экскурсоводам',
                                            value:
                                                '-${((stat['guide_costs'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ₽',
                                            color: Colors.purple,
                                          ),
                                          _StatRow(
                                            label: 'Всего расходы на персонал',
                                            value:
                                                '-${((stat['staff_costs'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} ₽',
                                            color: Colors.purple,
                                          ),
                                          const Divider(),
                                          _StatRow(
                                            label: 'Чистая прибыль',
                                            value:
                                                '${netProfit.toStringAsFixed(2)} ₽',
                                            color: netProfit >= 0
                                                ? Colors.green
                                                : Colors.red,
                                            isBold: true,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Доход - комиссии продавцам - расходы на персонал',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            } catch (e) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: const Icon(Icons.error_outline,
                                      color: Colors.red),
                                  title:
                                      const Text('Ошибка отображения данных'),
                                  subtitle: Text('$e'),
                                ),
                              );
                            }
                          }).toList(),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        } catch (e) {
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_statisticsFutureProvider);
              await ref.read(_statisticsFutureProvider.future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Ошибка обработки данных: $e'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () =>
                            ref.invalidate(_statisticsFutureProvider),
                        child: const Text('Повторить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

final _cancelledDatesFutureProvider =
    FutureProvider<List<CancelledExcursionDate>>((ref) async {
  final repository = ref.watch(excursionsRepositoryProvider);
  return repository.fetchCancelledDates();
});

class _CancelledExcursionsTab extends ConsumerWidget {
  const _CancelledExcursionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancelledDatesAsync = ref.watch(_cancelledDatesFutureProvider);
    final internetStatusAsync = ref.watch(internetStatusProvider);
    final hasInternet = internetStatusAsync.valueOrNull ?? true;
    final appBarColor =
        hasInternet ? Theme.of(context).colorScheme.primary : Colors.red;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        title: const Text('Отмененные экскурсии'),
        actions: [
          IconButton(
            color: Colors.white,
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(_cancelledDatesFutureProvider);
            },
          ),
        ],
      ),
      body: cancelledDatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text('Ошибка загрузки: $error'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      ref.invalidate(_cancelledDatesFutureProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        ),
        data: (cancelledDates) {
          if (cancelledDates.isEmpty) {
            return const Center(
              child: Text('Нет отмененных экскурсий'),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_cancelledDatesFutureProvider);
              await ref.read(_cancelledDatesFutureProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: cancelledDates.length,
              itemBuilder: (context, index) {
                final cancelled = cancelledDates[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.cancel, color: Colors.red),
                    title: Text(
                      cancelled.excursionTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Дата: ${DateFormat('dd.MM.yyyy', 'ru').format(cancelled.dateTime)}',
                        ),
                        Text(
                          'Время: ${cancelled.time}',
                        ),
                        Text(
                          'Отменена: ${DateFormat('dd.MM.yyyy HH:mm', 'ru').format(cancelled.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.restore, color: Colors.green),
                      tooltip: 'Восстановить',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Восстановить экскурсию?'),
                            content: Text(
                              'Вы уверены, что хотите восстановить экскурсию "${cancelled.excursionTitle}" на ${DateFormat('dd.MM.yyyy HH:mm', 'ru').format(cancelled.dateTime)}?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: const Text('Восстановить'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true && context.mounted) {
                          try {
                            await ref
                                .read(excursionsRepositoryProvider)
                                .restoreExcursionDate(
                                  excursionId: cancelled.excursionId,
                                  cancelledDateId: cancelled.id,
                                );
                            if (context.mounted) {
                              ref.invalidate(_cancelledDatesFutureProvider);
                              ref.invalidate(excursionsFutureProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Экскурсия восстановлена'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.all(16),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Ошибка: $e'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Показываем диалог для отмены экскурсии
          final result = await showDialog<Map<String, dynamic>>(
            context: context,
            builder: (context) => _CancelExcursionDialog(),
          );

          if (result != null && context.mounted) {
            try {
              await ref.read(excursionsRepositoryProvider).cancelExcursionDate(
                    excursionId: result['excursion_id'] as int,
                    dateTime: result['date_time'] as DateTime,
                  );
              if (context.mounted) {
                ref.invalidate(_cancelledDatesFutureProvider);
                ref.invalidate(excursionsFutureProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Экскурсия отменена'),
                    behavior: SnackBarBehavior.floating,
                    margin: EdgeInsets.all(16),
                  ),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Ошибка: $e'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            }
          }
        },
        child: const Icon(Icons.cancel),
        tooltip: 'Отменить экскурсию',
      ),
    );
  }
}

class _CancelExcursionDialog extends ConsumerStatefulWidget {
  const _CancelExcursionDialog();

  @override
  ConsumerState<_CancelExcursionDialog> createState() =>
      _CancelExcursionDialogState();
}

class _CancelExcursionDialogState
    extends ConsumerState<_CancelExcursionDialog> {
  Excursion? _selectedExcursion;
  DateTime? _selectedDateTime;

  // Получаем список доступных дат для выбранной экскурсии
  List<DateTime> _getAvailableDates(List<Excursion> allExcursions) {
    if (_selectedExcursion == null) return [];

    // Находим все записи этой экскурсии (развернутые по датам)
    final dates = allExcursions
        .where((e) => e.id == _selectedExcursion!.id)
        .map((e) => e.dateTime)
        .toSet() // Убираем дубликаты
        .toList()
      ..sort(); // Сортируем по дате

    return dates;
  }

  @override
  Widget build(BuildContext context) {
    final excursionsAsync = ref.watch(excursionsFutureProvider);

    return AlertDialog(
      title: const Text('Отменить экскурсию'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            excursionsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, _) => Text('Ошибка: $error'),
              data: (excursions) {
                if (excursions.isEmpty) {
                  return const Text('Нет доступных экскурсий');
                }

                // Фильтруем уникальные экскурсии по ID, так как API возвращает развернутые по датам
                final uniqueExcursions = <int, Excursion>{};
                for (final excursion in excursions) {
                  if (!uniqueExcursions.containsKey(excursion.id)) {
                    uniqueExcursions[excursion.id] = excursion;
                  }
                }
                final uniqueList = uniqueExcursions.values.toList()
                  ..sort((a, b) => a.title.compareTo(b.title));

                final availableDates = _getAvailableDates(excursions);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<Excursion>(
                      decoration: const InputDecoration(
                        labelText: 'Экскурсия',
                        border: OutlineInputBorder(),
                      ),
                      value: _selectedExcursion,
                      items: uniqueList.map((excursion) {
                        return DropdownMenuItem(
                          value: excursion,
                          child: Text(excursion.title),
                        );
                      }).toList(),
                      onChanged: (excursion) {
                        setState(() {
                          _selectedExcursion = excursion;
                          _selectedDateTime = null; // Сбрасываем выбранную дату
                        });
                      },
                    ),
                    if (_selectedExcursion != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Доступные даты и время:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (availableDates.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'Нет доступных дат для этой экскурсии',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: availableDates.length,
                            itemBuilder: (context, index) {
                              final dateTime = availableDates[index];
                              final isSelected = _selectedDateTime != null &&
                                  _selectedDateTime!.year == dateTime.year &&
                                  _selectedDateTime!.month == dateTime.month &&
                                  _selectedDateTime!.day == dateTime.day &&
                                  _selectedDateTime!.hour == dateTime.hour &&
                                  _selectedDateTime!.minute == dateTime.minute;

                              return Card(
                                color: isSelected
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                    : null,
                                child: ListTile(
                                  title: Text(
                                    DateFormat('dd.MM.yyyy', 'ru')
                                        .format(dateTime),
                                  ),
                                  subtitle: Text(
                                    DateFormat('HH:mm', 'ru').format(dateTime),
                                  ),
                                  trailing: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.green)
                                      : null,
                                  onTap: () {
                                    setState(() {
                                      _selectedDateTime = dateTime;
                                    });
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _selectedExcursion != null && _selectedDateTime != null
              ? () {
                  Navigator.of(context).pop({
                    'excursion_id': _selectedExcursion!.id,
                    'date_time': _selectedDateTime!,
                  });
                }
              : null,
          child: const Text('Отменить'),
        ),
      ],
    );
  }
}

final _statisticsFutureProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = ref.read(apiClientProvider);
  final response = await client.getJson(
    '/api/excursions/statistics',
    authenticated: true,
  );
  return response;
});

// Экран расчетных листов
class _SettlementsTab extends ConsumerStatefulWidget {
  const _SettlementsTab();

  @override
  ConsumerState<_SettlementsTab> createState() => _SettlementsTabState();
}

class _SettlementsTabState extends ConsumerState<_SettlementsTab>
    with SingleTickerProviderStateMixin {
  Seller? _selectedSeller;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final Set<int> _selectedBookingIds = {};
  bool _selectAll = false;
  late TabController _tabController;
  int _currentTabIndex = 0; // 0 = не рассчитано, 1 = рассчитано

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
        _selectedBookingIds.clear();
        _selectAll = false;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Расчетные листы'),
        bottom: _selectedSeller != null
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Не рассчитано'),
                  Tab(text: 'Рассчитано'),
                ],
              )
            : null,
      ),
      body: Column(
        children: [
          // Выбор продавца
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildSellerSelector(),
          ),
          // Фильтры по датам
          if (_selectedSeller != null) _buildDateFilters(),
          // Список продаж
          Expanded(
            child: _selectedSeller != null
                ? TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSalesList(settled: false),
                      _buildSalesList(settled: true),
                    ],
                  )
                : const Center(
                    child: Text('Выберите продавца'),
                  ),
          ),
          // Кнопка рассчитаться (только для таба "Не рассчитано")
          if (_selectedSeller != null &&
              _currentTabIndex == 0 &&
              _selectedBookingIds.isNotEmpty)
            _buildSettleButton(),
        ],
      ),
    );
  }

  Widget _buildSellerSelector() {
    final sellersAsync = ref.watch(_sellersFutureProvider);

    return sellersAsync.when(
      data: (sellers) {
        if (sellers.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Нет продавцов с бронированиями'),
            ),
          );
        }
        return DropdownButtonFormField<Seller>(
          decoration: const InputDecoration(
            labelText: 'Продавец',
            border: OutlineInputBorder(),
          ),
          value: _selectedSeller,
          items: sellers.map((seller) {
            return DropdownMenuItem(
              value: seller,
              child: Text(seller.name),
            );
          }).toList(),
          onChanged: (seller) {
            setState(() {
              _selectedSeller = seller;
              _selectedBookingIds.clear();
              _selectAll = false;
              _dateFrom = null;
              _dateTo = null;
            });
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        return Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  'Ошибка загрузки продавцов: $error',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(_sellersFutureProvider);
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDateFilters() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _dateFrom != null
                        ? DateFormat('dd.MM.yyyy').format(_dateFrom!)
                        : 'С даты',
                  ),
                  onPressed: () => _showCalendar(context, isFromDate: true),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    _dateTo != null
                        ? DateFormat('dd.MM.yyyy').format(_dateTo!)
                        : 'По дату',
                  ),
                  onPressed: () => _showCalendar(context, isFromDate: false),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showCalendar(BuildContext context, {required bool isFromDate}) {
    showDialog(
      context: context,
      builder: (context) => _CalendarDialog(
        selectedDate: isFromDate ? _dateFrom : _dateTo,
        onDateSelected: (date) {
          setState(() {
            if (isFromDate) {
              _dateFrom = date;
            } else {
              _dateTo = date;
            }
            _selectedBookingIds.clear();
            _selectAll = false;
          });
          Navigator.of(context).pop();
        },
        sellerId: _selectedSeller?.id,
      ),
    );
  }

  Widget _buildSalesList({required bool settled}) {
    final salesAsync = ref.watch(
      _sellerSalesFutureProvider(
        _SellerSalesParams(
          sellerId: _selectedSeller!.id,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          settled: settled,
        ),
      ),
    );

    return salesAsync.when(
      data: (response) {
        if (response.sales.isEmpty) {
          return Center(
            child: Text(
                settled ? 'Нет рассчитанных продаж' : 'Нет продаж для расчета'),
          );
        }

        return Column(
          children: [
            // Чекбокс "Выбрать все" (только для не рассчитанных)
            if (!settled)
              CheckboxListTile(
                title: const Text('Выбрать все'),
                value: _selectAll,
                onChanged: (value) {
                  setState(() {
                    _selectAll = value ?? false;
                    if (_selectAll) {
                      _selectedBookingIds.addAll(
                        response.sales.map((s) => s.id),
                      );
                    } else {
                      _selectedBookingIds.clear();
                    }
                  });
                },
              ),
            if (!settled) const Divider(),
            // Список продаж
            Expanded(
              child: ListView.builder(
                itemCount: response.sales.length,
                itemBuilder: (context, index) {
                  final sale = response.sales[index];
                  final isSelected =
                      !settled && _selectedBookingIds.contains(sale.id);
                  final isEven = index % 2 == 0;

                  return Card(
                    color: isEven ? Colors.grey.shade50 : Colors.white,
                    child: settled
                        ? ListTile(
                            title: Text(sale.customerName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${sale.excursion.title}'),
                                if (sale.excursion.dateTime != null)
                                  Text(
                                    DateFormat('dd.MM.yyyy HH:mm')
                                        .format(sale.excursion.dateTime!),
                                  ),
                                Text(
                                    '${sale.passengerType} - ${sale.price.toStringAsFixed(2)} ₽'),
                                if (sale.settlement != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Рассчитано: ${DateFormat('dd.MM.yyyy').format(sale.settlement!.settlementDate)}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${sale.price.toStringAsFixed(2)} ₽',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel,
                                      color: Colors.red),
                                  tooltip: 'Удалить из расчета',
                                  onPressed: () => _removeBookingFromSettlement(
                                    settlementId: sale.settlement!.id,
                                    bookingId: sale.id,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value ?? false) {
                                  _selectedBookingIds.add(sale.id);
                                } else {
                                  _selectedBookingIds.remove(sale.id);
                                }
                                _selectAll = _selectedBookingIds.length ==
                                    response.sales.length;
                              });
                            },
                            title: Text(sale.customerName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${sale.excursion.title}'),
                                if (sale.excursion.dateTime != null)
                                  Text(
                                    DateFormat('dd.MM.yyyy HH:mm')
                                        .format(sale.excursion.dateTime!),
                                  ),
                                Text(
                                    '${sale.passengerType} - ${sale.price.toStringAsFixed(2)} ₽'),
                              ],
                            ),
                            secondary: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${sale.price.toStringAsFixed(2)} ₽',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.check_circle),
                                  tooltip: 'Рассчитаться',
                                  onPressed: () =>
                                      _settleSingleBooking(sale.id),
                                ),
                              ],
                            ),
                          ),
                  );
                },
              ),
            ),
            // Итого
            Column(
              children: [
                // Общая статистика за период (если выбраны даты)
                if (response.periodStats != null)
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Общая сумма за период:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Всего продаж:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                            Text(
                              '${response.periodStats!.totalSales.toStringAsFixed(2)} ₽ (${response.periodStats!.totalCount})',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Рассчитано:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green.shade700,
                              ),
                            ),
                            Text(
                              '${response.periodStats!.settledSales.toStringAsFixed(2)} ₽ (${response.periodStats!.settledCount})',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Не рассчитано:',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.red.shade700,
                              ),
                            ),
                            Text(
                              '${response.periodStats!.unsettledSales.toStringAsFixed(2)} ₽ (${response.periodStats!.unsettledCount})',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                // Итого в текущем табе
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.vertical(
                      top: response.periodStats != null
                          ? Radius.zero
                          : const Radius.circular(16),
                      bottom: const Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        settled ? 'Итого рассчитано:' : 'Итого не рассчитано:',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        '${response.totalAmount.toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) {
        return Card(
          color: Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(height: 8),
                Text(
                  'Ошибка загрузки продаж: $error',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    ref.invalidate(
                      _sellerSalesFutureProvider(
                        _SellerSalesParams(
                          sellerId: _selectedSeller!.id,
                          dateFrom: _dateFrom,
                          dateTo: _dateTo,
                          settled: _currentTabIndex == 1,
                        ),
                      ),
                    );
                  },
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettleButton() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.check_circle),
          label: Text(
            'Рассчитаться (${_selectedBookingIds.length})',
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: () => _settleSelectedBookings(),
        ),
      ),
    );
  }

  Future<void> _settleSingleBooking(int bookingId) async {
    await _settleBookings([bookingId]);
  }

  Future<void> _settleSelectedBookings() async {
    if (_selectedBookingIds.isEmpty) return;
    await _settleBookings(_selectedBookingIds.toList());
  }

  Future<void> _settleBookings(List<int> bookingIds) async {
    if (_selectedSeller == null || bookingIds.isEmpty) return;

    try {
      await ref.read(settlementsRepositoryProvider).createSettlement(
            sellerId: _selectedSeller!.id,
            bookingIds: bookingIds,
            dateFrom: _dateFrom,
            dateTo: _dateTo,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Расчет создан для ${bookingIds.length} ${bookingIds.length == 1 ? 'продажи' : 'продаж'}. Продажи перемещены в таб "Рассчитано"',
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Перейти',
              onPressed: () {
                _tabController
                    .animateTo(1); // Переключаемся на таб "Рассчитано"
              },
            ),
          ),
        );

        setState(() {
          _selectedBookingIds.removeAll(bookingIds);
          _selectAll = false;
        });

        // Обновляем оба таба (рассчитанные и не рассчитанные) и статус календаря
        ref.invalidate(
          _sellerSalesFutureProvider(
            _SellerSalesParams(
              sellerId: _selectedSeller!.id,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              settled: false,
            ),
          ),
        );
        ref.invalidate(
          _sellerSalesFutureProvider(
            _SellerSalesParams(
              sellerId: _selectedSeller!.id,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              settled: true,
            ),
          ),
        );
        ref.invalidate(_calendarStatusFutureProvider(_selectedSeller!.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _removeBookingFromSettlement({
    required int settlementId,
    required int bookingId,
  }) async {
    if (_selectedSeller == null) return;

    // Подтверждение удаления
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить из расчета?'),
        content: const Text(
          'Вы уверены, что хотите удалить эту продажу из расчета? Она вернется в таб "Не рассчитано".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await ref
          .read(settlementsRepositoryProvider)
          .removeBookingFromSettlement(
            settlementId: settlementId,
            bookingId: bookingId,
          );

      if (mounted) {
        final settlementDeleted =
            response['settlement_deleted'] as bool? ?? false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              settlementDeleted
                  ? 'Продажа удалена. Расчет отменен (не осталось продаж)'
                  : 'Продажа удалена из расчета',
            ),
          ),
        );

        // Обновляем оба таба и статус календаря
        ref.invalidate(
          _sellerSalesFutureProvider(
            _SellerSalesParams(
              sellerId: _selectedSeller!.id,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              settled: false,
            ),
          ),
        );
        ref.invalidate(
          _sellerSalesFutureProvider(
            _SellerSalesParams(
              sellerId: _selectedSeller!.id,
              dateFrom: _dateFrom,
              dateTo: _dateTo,
              settled: true,
            ),
          ),
        );
        ref.invalidate(_calendarStatusFutureProvider(_selectedSeller!.id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при удалении продажи из расчета: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }
}

// Календарь с цветовой индикацией для расчетных листов
class _CalendarDialog extends ConsumerStatefulWidget {
  final DateTime? selectedDate;
  final Function(DateTime) onDateSelected;
  final int? sellerId;

  const _CalendarDialog({
    required this.selectedDate,
    required this.onDateSelected,
    this.sellerId,
  });

  @override
  ConsumerState<_CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends ConsumerState<_CalendarDialog> {
  DateTime _currentMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.selectedDate != null) {
      _currentMonth =
          DateTime(widget.selectedDate!.year, widget.selectedDate!.month);
    }
  }

  Map<String, String> _getDaysStatus() {
    if (widget.sellerId == null) return {};
    final statusAsync = ref.watch(
      _calendarStatusFutureProvider(widget.sellerId!),
    );
    return statusAsync.valueOrNull ?? {};
  }

  Color _getDayColor(DateTime date, Map<String, String> daysStatus) {
    final dateKey = date.toIso8601String().split('T')[0];
    final status = daysStatus[dateKey];

    if (status == null) return Colors.transparent;

    switch (status) {
      case 'settled':
        return Colors.green; // Все рассчитаны
      case 'unsettled':
        return Colors.red; // Все не рассчитаны
      case 'partial':
        return Colors.orange; // Смешанный статус
      default:
        return Colors.transparent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysStatus = _getDaysStatus();
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday;
    final daysInMonth = lastDay.day;

    // Названия дней недели
    final weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

    // Создаем список дней месяца
    final days = <Widget>[];

    // Добавляем заголовки дней недели
    for (var weekday in weekdays) {
      days.add(
        Center(
          child: Text(
            weekday,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      );
    }

    // Добавляем пустые ячейки до первого дня месяца
    for (int i = 1; i < firstWeekday; i++) {
      days.add(const SizedBox());
    }

    // Добавляем дни месяца
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final isSelected = widget.selectedDate != null &&
          widget.selectedDate!.year == date.year &&
          widget.selectedDate!.month == date.month &&
          widget.selectedDate!.day == date.day;
      final dayColor = _getDayColor(date, daysStatus);
      final hasStatus =
          daysStatus.containsKey(date.toIso8601String().split('T')[0]);

      days.add(
        GestureDetector(
          onTap: () => widget.onDateSelected(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : (hasStatus
                      ? dayColor.withOpacity(0.3)
                      : Colors.transparent),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : (hasStatus ? dayColor : Colors.grey.shade300),
                width: isSelected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : (hasStatus ? dayColor : Colors.black),
                  fontWeight: isSelected || hasStatus
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth =
                    DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
          ),
          Text(
            DateFormat('MMMM yyyy', 'ru_RU').format(_currentMonth),
            style: const TextStyle(fontSize: 18),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _currentMonth =
                    DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) => days[index],
            ),
            const SizedBox(height: 16),
            // Легенда
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem(Colors.green, 'Все рассчитаны'),
                _buildLegendItem(Colors.red, 'Не рассчитаны'),
                _buildLegendItem(Colors.orange, 'Частично'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

final _sellersFutureProvider = FutureProvider<List<Seller>>((ref) {
  final repository = ref.watch(settlementsRepositoryProvider);
  return repository.fetchSellers();
});

class _SellerSalesParams {
  final int sellerId;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool settled;

  _SellerSalesParams({
    required this.sellerId,
    this.dateFrom,
    this.dateTo,
    this.settled = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SellerSalesParams &&
          runtimeType == other.runtimeType &&
          sellerId == other.sellerId &&
          dateFrom == other.dateFrom &&
          dateTo == other.dateTo &&
          settled == other.settled;

  @override
  int get hashCode =>
      sellerId.hashCode ^
      dateFrom.hashCode ^
      dateTo.hashCode ^
      settled.hashCode;
}

final _sellerSalesFutureProvider =
    FutureProvider.family<SellerSalesResponse, _SellerSalesParams>(
        (ref, params) {
  final repository = ref.watch(settlementsRepositoryProvider);
  return repository.fetchSellerSales(
    params.sellerId,
    dateFrom: params.dateFrom,
    dateTo: params.dateTo,
    settled: params.settled,
  );
});

final _calendarStatusFutureProvider =
    FutureProvider.family<Map<String, String>, int>((ref, sellerId) {
  final repository = ref.watch(settlementsRepositoryProvider);
  return repository.fetchCalendarStatus(sellerId);
});
