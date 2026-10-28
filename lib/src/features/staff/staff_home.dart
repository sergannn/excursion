import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/user.dart';
import '../../data/models/stop.dart';
import '../../data/models/bus_seat.dart';
import '../../data/models/excursion.dart';
import '../../data/providers.dart';
import '../auth/auth_controller.dart';
import 'assignments_controller.dart';
import '../../core/services/internet_connection_service.dart';

final assignmentsControllerProvider =
    Provider.family<AssignmentsController, User>(
  (ref, user) {
    final assignmentsRepo = ref.watch(assignmentsRepositoryProvider);
    final controller = AssignmentsController(
      user: user,
      assignmentsRepository: assignmentsRepo,
    );
    ref.onDispose(() => controller.dispose());
    return controller;
  },
);

class StaffHomePage extends ConsumerStatefulWidget {
  const StaffHomePage({super.key, required this.user});

  final User user;

  @override
  ConsumerState<StaffHomePage> createState() => _StaffHomePageState();
}

class _StaffHomePageState extends ConsumerState<StaffHomePage> {
  DateTime? _selectedDateFrom;
  DateTime? _selectedDateTo;
  final Set<int> _expandedExcursionIds = {};

  @override
  void initState() {
    super.initState();
    // Инициализируем контроллер при открытии страницы
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(assignmentsControllerProvider(widget.user));
    });
  }

  @override
  Widget build(BuildContext context) {
    // Определяем, водитель это или гид
    final isDriver = widget.user.roleId == 3;
    final normalizedRole = widget.user.role.trim().toLowerCase();
    final isGuide = normalizedRole.contains('гид') ||
        normalizedRole.contains('guide') ||
        normalizedRole.contains('экскурсовод');
    final showTabs = isDriver || isGuide;
    final excursionsAsync = ref.watch(
      showTabs
          ? staffExcursionsFutureProvider(widget.user.id)
          : excursionsFutureProvider,
    );
    final staffProfitAsync =
        ref.watch(staffProfitFutureProvider(widget.user.id));
    final formatter = DateFormat('dd.MM.yyyy HH:mm');

    // Подписываемся на контроллер назначений (только для водителей и гидов)
    // Уведомления показываются автоматически в контроллере при обнаружении новых назначений
    if (isDriver || isGuide) {
      ref.watch(assignmentsControllerProvider(widget.user));
    }

    final appBarTitle = isDriver
        ? 'Кабинет водителя — ${widget.user.name}'
        : isGuide
            ? 'Кабинет экскурсовода — ${widget.user.name}'
            : 'Расписание — ${widget.user.name}';

    // Отслеживаем статус интернета
    final internetStatusAsync = ref.watch(internetStatusProvider);
    final hasInternet = internetStatusAsync.valueOrNull ?? true;

    // Определяем цвет фона AppBar в зависимости от статуса интернета
    final appBarColor =
        hasInternet ? Theme.of(context).colorScheme.primary : Colors.red;

    final scaffold = Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white, // Белый цвет для всех элементов AppBar
        title: Text(
          appBarTitle,
          style:
              const TextStyle(color: Colors.white), // Явно указываем белый цвет
        ),
        bottom: showTabs
            ? TabBar(
                tabs: const [
                  Tab(text: 'Предстоящие'),
                  Tab(text: 'Прошедшие'),
                  Tab(icon: Icon(Icons.currency_ruble), text: 'Прибыль'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'Выйти',
            icon: const Icon(Icons.logout,
                color: Colors.white), // Явно указываем белый цвет
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: showTabs
          ? excursionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Ошибка: $error')),
              data: (items) {
                // Получаем данные о прибыли для передачи в ExpansionTile
                final profitData = staffProfitAsync.valueOrNull;

                // Для водителей/гидов (showTabs = true) мы уже получаем только их бронирования
                // через /api/bookings/driver, поэтому все экскурсии уже "назначены"
                // Для остальных ролей фильтруем по assignedStaff
                final assigned = showTabs
                    ? items // Для водителей/гидов берем все (уже отфильтровано на бэкенде)
                    : items
                        .where(
                          (excursion) => excursion.assignedStaff
                              .any((staff) => staff.id == widget.user.id),
                        )
                        .toList();

                Widget buildList(List<Excursion> list, String emptyText) {
                  if (list.isEmpty) {
                    return Center(child: Text(emptyText));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final excursion = list[index];
                      // Получаем роль пользователя в экскурсии
                      final staffMember = excursion.assignedStaff
                          .where((staff) => staff.id == widget.user.id)
                          .firstOrNull;
                      final role = staffMember?.roleInExcursion ??
                          (isDriver ? 'driver' : 'guide');
                      final isExpanded =
                          _expandedExcursionIds.contains(excursion.id);
                      return Card(
                        elevation: isExpanded ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isExpanded
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: isExpanded ? 2 : 0,
                          ),
                        ),
                        child: ExpansionTile(
                          title: Text(
                            excursion.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          subtitle: Text(
                            _buildExcursionHeaderMeta(excursion, formatter),
                          ),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedExcursionIds.add(excursion.id);
                              } else {
                                _expandedExcursionIds.remove(excursion.id);
                              }
                            });
                          },
                          initiallyExpanded: isExpanded,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _CollapsibleInfoRow(
                                    role: role,
                                    description: excursion.description,
                                    isDriver: isDriver,
                                    isGuide: isGuide,
                                    excursionId: excursion.id,
                                    excursionDate: excursion.dateTime,
                                    profitData: profitData,
                                  ),
                                  // Ведомость по остановкам и расчетам
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Ведомость экскурсии:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _BookedStopsFromSeats(
                                    excursion: excursion,
                                    busSeats: excursion.busSeats,
                                  ),
                                  const SizedBox(height: 16),
                                  // Полный список остановок — убираем в collapsible
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Все остановки маршрута',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    children: [
                                      FutureBuilder<List<Stop>>(
                                        future: ref
                                            .read(stopsRepositoryProvider)
                                            .fetchStopsForExcursion(
                                                excursion.id),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError) {
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.all(8.0),
                                              child: Text(
                                                'Ошибка загрузки остановок: ${snapshot.error}',
                                                style: TextStyle(
                                                  color: Colors.red.shade700,
                                                ),
                                              ),
                                            );
                                          }
                                          final stops = snapshot.data ?? [];
                                          if (stops.isEmpty) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child:
                                                  Text('Остановки не указаны'),
                                            );
                                          }
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: stops
                                                .map((stop) => Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                              bottom: 4),
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.location_on,
                                                            size: 16,
                                                            color: Colors.grey,
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Expanded(
                                                            child:
                                                                Text(stop.name),
                                                          ),
                                                        ],
                                                      ),
                                                    ))
                                                .toList(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }

                if (assigned.isEmpty) {
                  return const Center(
                    child: Text('Для вас пока нет назначенных экскурсий'),
                  );
                }

                if (!showTabs) {
                  assigned.sort((a, b) => a.dateTime.compareTo(b.dateTime));
                  return buildList(
                    assigned,
                    'Для вас пока нет назначенных экскурсий',
                  );
                }

                final upcomingList = assigned.where((e) => !e.isPast).toList()
                  ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
                final pastList = assigned.where((e) => e.isPast).toList()
                  ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

                return TabBarView(
                  children: [
                    buildList(
                      upcomingList,
                      'Нет предстоящих экскурсий',
                    ),
                    buildList(
                      pastList,
                      'Нет прошедших экскурсий',
                    ),
                    _ProfitTab(
                      staffProfitAsync: staffProfitAsync,
                      selectedDateFrom: _selectedDateFrom,
                      selectedDateTo: _selectedDateTo,
                      onDateFromChanged: (date) {
                        setState(() {
                          _selectedDateFrom = date;
                        });
                      },
                      onDateToChanged: (date) {
                        setState(() {
                          _selectedDateTo = date;
                        });
                      },
                      onDatesCleared: () {
                        setState(() {
                          _selectedDateFrom = null;
                          _selectedDateTo = null;
                        });
                      },
                      formatter: formatter,
                    ),
                  ],
                );
              },
            )
          : excursionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Ошибка: $error')),
              data: (items) {
                final assigned = items
                    .where(
                      (excursion) => excursion.assignedStaff
                          .any((staff) => staff.id == widget.user.id),
                    )
                    .toList();

                if (assigned.isEmpty) {
                  return const Center(
                    child: Text('Для вас пока нет назначенных экскурсий'),
                  );
                }

                assigned.sort((a, b) => a.dateTime.compareTo(b.dateTime));
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: assigned.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final excursion = assigned[index];
                    final staffMember = excursion.assignedStaff
                        .where((staff) => staff.id == widget.user.id)
                        .firstOrNull;
                    final role = staffMember?.roleInExcursion ??
                        (isDriver ? 'driver' : 'guide');
                    final isExpanded =
                        _expandedExcursionIds.contains(excursion.id);
                    return Card(
                      elevation: isExpanded ? 4 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isExpanded
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: isExpanded ? 2 : 0,
                        ),
                      ),
                      child: ExpansionTile(
                        title: Text(
                          excursion.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          _buildExcursionHeaderMeta(excursion, formatter),
                        ),
                        onExpansionChanged: (expanded) {
                          setState(() {
                            if (expanded) {
                              _expandedExcursionIds.add(excursion.id);
                            } else {
                              _expandedExcursionIds.remove(excursion.id);
                            }
                          });
                        },
                        initiallyExpanded: isExpanded,
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _CollapsibleInfoRow(
                                  role: role,
                                  description: excursion.description,
                                  isDriver: isDriver,
                                  isGuide: isGuide,
                                  excursionId: excursion.id,
                                  excursionDate: excursion.dateTime,
                                  profitData: staffProfitAsync.valueOrNull,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Ведомость экскурсии:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _BookedStopsFromSeats(
                                  excursion: excursion,
                                  busSeats: excursion.busSeats,
                                ),
                                const SizedBox(height: 16),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Все остановки маршрута',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  children: [
                                    FutureBuilder<List<Stop>>(
                                      future: ref
                                          .read(stopsRepositoryProvider)
                                          .fetchStopsForExcursion(excursion.id),
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Center(
                                              child:
                                                  CircularProgressIndicator(),
                                            ),
                                          );
                                        }
                                        if (snapshot.hasError) {
                                          return Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Text(
                                              'Ошибка загрузки остановок: ${snapshot.error}',
                                              style: TextStyle(
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          );
                                        }
                                        final stops = snapshot.data ?? [];
                                        if (stops.isEmpty) {
                                          return const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Text('Остановки не указаны'),
                                          );
                                        }
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: stops
                                              .map((stop) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 4),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.location_on,
                                                          size: 16,
                                                          color: Colors.grey,
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                          child:
                                                              Text(stop.name),
                                                        ),
                                                      ],
                                                    ),
                                                  ))
                                              .toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );

    if (showTabs) {
      return DefaultTabController(length: 3, child: scaffold);
    }
    return scaffold;
  }
}

class _SeatsGrid extends StatelessWidget {
  const _SeatsGrid({required this.busSeats});

  final List<BusSeat> busSeats;

  @override
  Widget build(BuildContext context) {
    if (busSeats.isEmpty) {
      return const Text('Схема мест недоступна');
    }

    final sorted = [...busSeats]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sorted.map((seat) {
        final booking = seat.booking;
        final hasBooking = booking != null;
        final label = StringBuffer()..write(seat.seatNumber);
        if (hasBooking && booking.customerName.isNotEmpty) {
          label.write(' — ${booking.customerName}');
        }

        // Добавляем информацию о продавце
        final sellerInfo = <String>[];
        if (seat.bookedByInfo != null) {
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
                if (booking.customerPhone.isNotEmpty) booking.customerPhone,
                ...sellerInfo,
              ].where((e) => e.isNotEmpty).join('\n')
            : (seat.status == 'available'
                ? 'Свободно'
                : (seat.bookedByInfo != null &&
                        seat.bookedByInfo!.name.isNotEmpty
                    ? seat.bookedByInfo!.name
                    : 'Занято'));

        // Используем цвет продавца, если он есть, иначе стандартные цвета
        Color seatColor;
        if (seat.bookedByInfo?.color != null &&
            seat.bookedByInfo!.color!.isNotEmpty) {
          try {
            final hexColor = seat.bookedByInfo!.color!;
            seatColor =
                Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
          } catch (e) {
            seatColor = hasBooking
                ? Colors.blue.shade100
                : seat.status == 'available'
                    ? Colors.green.shade100
                    : Colors.red.shade100;
          }
        } else {
          seatColor = hasBooking
              ? Colors.blue.shade100
              : seat.status == 'available'
                  ? Colors.green.shade100
                  : Colors.red.shade100;
        }

        return Container(
          width: 140,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: seatColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
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

class _BookedStopsFromSeats extends StatelessWidget {
  const _BookedStopsFromSeats({
    required this.excursion,
    required this.busSeats,
  });

  final Excursion excursion;
  final List<BusSeat> busSeats;

  @override
  Widget build(BuildContext context) {
    final stops = _buildStopManifest(busSeats);
    final transportCost = _resolveStaffCost(excursion, 'driver');
    final guideCost = _resolveStaffCost(excursion, 'guide');
    final entryTicketsCost = _resolveEntryTicketsCost(excursion, busSeats);
    final revenue = _resolveRevenue(excursion, busSeats);
    final total = revenue - transportCost - guideCost - entryTicketsCost;
    final transportDetails = _resolveTransportDetails(excursion);
    final guideDetails = _resolveGuideDetails(excursion);

    if (stops.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Text('Остановки будут показаны после бронирований.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  final sellerColor = seller.color?.isNotEmpty == true
                      ? _parseHexColor(seller.color!)
                      : Colors.orange.shade200;
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
                            color: sellerColor,
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
                              const SizedBox(height: 2),
                              Text(
                                seller.seats
                                    .map((seat) => _passengerTypeLabel(
                                          seat.booking?.passengerType ?? '',
                                        ))
                                    .where((value) => value.isNotEmpty)
                                    .join(', '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FinanceRow(
                      label: 'Транспорт',
                      subtitle: transportDetails,
                      value: '${transportCost.toStringAsFixed(0)} ₽',
                    ),
                    const SizedBox(height: 6),
                    _FinanceRow(
                      label: 'Экскурсовод',
                      subtitle: guideDetails,
                      value: '${guideCost.toStringAsFixed(0)} ₽',
                    ),
                    const SizedBox(height: 6),
                    _FinanceRow(
                      label: 'Входные билеты',
                      value: '${entryTicketsCost.toStringAsFixed(0)} ₽',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Свободные места: ${excursion.availableSeatsCount}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Выручка: ${revenue.toStringAsFixed(0)} ₽',
                      textAlign: TextAlign.right,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Итого: ${total.toStringAsFixed(0)} ₽',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinanceRow extends StatelessWidget {
  const _FinanceRow({
    required this.label,
    this.subtitle,
    required this.value,
  });

  final String label;
  final String? subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
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
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ManifestStopGroup {
  const _ManifestStopGroup({
    required this.title,
    required this.order,
    required this.seats,
    required this.sellers,
  });

  final String title;
  final int order;
  final List<BusSeat> seats;
  final List<_ManifestSellerGroup> sellers;
}

class _ManifestSellerGroup {
  const _ManifestSellerGroup({
    required this.name,
    required this.color,
    required this.seats,
  });

  final String name;
  final String? color;
  final List<BusSeat> seats;
}

List<_ManifestStopGroup> _buildStopManifest(List<BusSeat> busSeats) {
  final groupedStops = <String, List<BusSeat>>{};

  for (final seat in busSeats) {
    final booking = seat.booking;
    final stopTitle = booking?.stopTitle?.trim() ?? '';
    if (stopTitle.isEmpty) {
      continue;
    }
    groupedStops.putIfAbsent(stopTitle, () => []).add(seat);
  }

  final result = groupedStops.entries.map((entry) {
    final seats = [...entry.value]
      ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
    final stopOrders = seats
        .map((seat) => seat.booking?.stopOrder)
        .whereType<int>()
        .toList()
      ..sort();
    final stopOrder = stopOrders.isNotEmpty ? stopOrders.first : 9999;

    final sellersMap = <String, List<BusSeat>>{};
    for (final seat in seats) {
      final sellerName = seat.bookedByInfo?.name.trim().isNotEmpty == true
          ? seat.bookedByInfo!.name.trim()
          : 'Без продавца';
      sellersMap.putIfAbsent(sellerName, () => []).add(seat);
    }

    final sellers = sellersMap.entries.map((sellerEntry) {
      final sellerSeats = [...sellerEntry.value]
        ..sort((a, b) => a.seatNumber.compareTo(b.seatNumber));
      return _ManifestSellerGroup(
        name: sellerEntry.key,
        color: sellerSeats.first.bookedByInfo?.color,
        seats: sellerSeats,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return _ManifestStopGroup(
      title: entry.key,
      order: stopOrder,
      seats: seats,
      sellers: sellers,
    );
  }).toList()
    ..sort((a, b) {
      final orderCompare = a.order.compareTo(b.order);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return a.title.compareTo(b.title);
    });

  return result;
}

String _buildExcursionHeaderMeta(Excursion excursion, DateFormat formatter) {
  return '${formatter.format(excursion.dateTime)} • '
      'Места ${excursion.bookedSeatsCount}/${excursion.maxSeats}';
}

String _resolveTransportDetails(Excursion excursion) {
  final labels = excursion.busAssignments
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

String _resolveGuideDetails(Excursion excursion) {
  final labels = excursion.assignedStaff
      .where((staff) => staff.roleInExcursion == 'guide')
      .map((staff) => staff.name.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  if (labels.isEmpty) {
    return 'не назначен';
  }

  return labels.join(', ');
}

double _resolveStaffCost(Excursion excursion, String staffType) {
  final actualBookedSeats =
      excursion.busSeats.where((seat) => seat.booking != null).length;

  if (actualBookedSeats <= 0) {
    return 0;
  }

  final hasAssignedStaff = excursion.assignedStaff.any(
    (staff) => staff.roleInExcursion == staffType,
  );
  if (!hasAssignedStaff) {
    return 0;
  }

  final manualAssignments = excursion.assignedStaff
      .where(
        (staff) =>
            staff.roleInExcursion == staffType && staff.manualAmount != null,
      )
      .toList();
  if (manualAssignments.isNotEmpty) {
    return manualAssignments.first.manualAmount!;
  }

  final matchingPrice = excursion.staffPrices.firstWhereOrNull((price) {
    if (price.staffType != staffType) {
      return false;
    }
    if (actualBookedSeats < price.minPassengers) {
      return false;
    }
    if (price.maxPassengers != null &&
        actualBookedSeats > price.maxPassengers!) {
      return false;
    }
    return true;
  });

  return matchingPrice?.price ?? 0;
}

double _resolveRevenue(Excursion excursion, List<BusSeat> busSeats) {
  return busSeats.fold<double>(0, (sum, seat) {
    final booking = seat.booking;
    if (booking == null) {
      return sum;
    }
    if (booking.price != null) {
      return sum + booking.price!;
    }
    final tariff =
        excursion.tariffs[booking.passengerType] ?? excursion.tariffs['adult'];
    if (tariff == null) {
      return sum;
    }
    final fallbackPrice = booking.withEntry
        ? (tariff.priceWithEntry ?? tariff.price)
        : (tariff.priceWithoutEntry ?? tariff.price);
    return sum + fallbackPrice;
  });
}

double _resolveEntryTicketsCost(Excursion excursion, List<BusSeat> busSeats) {
  return busSeats.fold<double>(0, (sum, seat) {
    final booking = seat.booking;
    if (booking == null || !booking.withEntry) {
      return sum;
    }
    final tariff =
        excursion.tariffs[booking.passengerType] ?? excursion.tariffs['adult'];
    if (tariff == null) {
      return sum;
    }
    final withEntry = tariff.priceWithEntry ?? tariff.price;
    final withoutEntry = tariff.priceWithoutEntry ?? tariff.price;
    final diff = withEntry - withoutEntry;
    return sum + (diff > 0 ? diff : 0);
  });
}

String _passengerTypeLabel(String value) {
  switch (value.toLowerCase()) {
    case 'adult':
      return 'Взрослый';
    case 'child':
      return 'Детский';
    case 'senior':
      return 'Пенсионер';
    case 'disabled':
      return 'Инвалид';
    case 'special':
      return 'Спеццена';
    case 'concession':
      return 'Льготный';
    default:
      return value;
  }
}

Color _parseHexColor(String hexColor) {
  try {
    return Color(
      int.parse(hexColor.replaceFirst('#', ''), radix: 16) + 0xFF000000,
    );
  } catch (_) {
    return Colors.orange.shade200;
  }
}

class _SeatCard extends StatelessWidget {
  const _SeatCard({required this.seat});

  final BusSeat seat;

  @override
  Widget build(BuildContext context) {
    final seatNumber = seat.seatNumber;

    return InkWell(
      onTap: () {
        _showSeatDetails(context, seat);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade300),
        ),
        child: Text(
          'Место №$seatNumber',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Colors.blue,
          ),
        ),
      ),
    );
  }

  void _showSeatDetails(BuildContext context, BusSeat seat) {
    final booking = seat.booking;
    final seatNumber = seat.seatNumber;
    final customerName = booking?.customerName ?? '';
    final customerPhone = booking?.customerPhone ?? '';
    final sellerInfo = seat.bookedByInfo;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Место №$seatNumber',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Имя и телефон по горизонтали
            if (customerName.isNotEmpty || customerPhone.isNotEmpty) ...[
              Row(
                children: [
                  if (customerName.isNotEmpty) ...[
                    const Icon(Icons.person, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                  if (customerPhone.isNotEmpty) ...[
                    if (customerName.isNotEmpty) const SizedBox(width: 16),
                    const Icon(Icons.phone, size: 18, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        customerPhone,
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],
            // Продавец ниже
            if (sellerInfo != null && sellerInfo.name.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.amber.shade200,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    if (sellerInfo.color != null &&
                        sellerInfo.color!.isNotEmpty)
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _parseColor(sellerInfo.color!),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.grey.shade400,
                            width: 1.5,
                          ),
                        ),
                      )
                    else
                      const Icon(
                        Icons.person_outline,
                        size: 20,
                        color: Colors.amber,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Продавец',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sellerInfo.name,
                            style: TextStyle(
                              color: Colors.grey.shade900,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.grey;
    }
  }
}

class _CollapsibleInfoRow extends StatefulWidget {
  const _CollapsibleInfoRow({
    required this.role,
    required this.description,
    required this.isDriver,
    required this.isGuide,
    required this.excursionId,
    required this.excursionDate,
    required this.profitData,
  });

  final String role;
  final String description;
  final bool isDriver;
  final bool isGuide;
  final int excursionId;
  final DateTime excursionDate;
  final Map<String, dynamic>? profitData;

  @override
  State<_CollapsibleInfoRow> createState() => _CollapsibleInfoRowState();
}

class _CollapsibleInfoRowState extends State<_CollapsibleInfoRow> {
  bool _isDescriptionExpanded = false;
  bool _isProfitExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _isDescriptionExpanded = !_isDescriptionExpanded;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const Spacer(),
                      Icon(
                        _isDescriptionExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.isDriver || widget.isGuide) ...[
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _isProfitExpanded = !_isProfitExpanded;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_ruble, color: Colors.green),
                        const Spacer(),
                        Icon(
                          _isProfitExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: Colors.green,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (_isDescriptionExpanded && widget.description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(widget.description),
          ),
        ],
        if (_isProfitExpanded && (widget.isDriver || widget.isGuide)) ...[
          const SizedBox(height: 8),
          _ProfitDetails(
            excursionId: widget.excursionId,
            excursionDate: widget.excursionDate,
            profitData: widget.profitData,
          ),
        ],
      ],
    );
  }
}

class _ProfitTab extends StatelessWidget {
  const _ProfitTab({
    required this.staffProfitAsync,
    required this.selectedDateFrom,
    required this.selectedDateTo,
    required this.onDateFromChanged,
    required this.onDateToChanged,
    required this.onDatesCleared,
    required this.formatter,
  });

  final AsyncValue<Map<String, dynamic>> staffProfitAsync;
  final DateTime? selectedDateFrom;
  final DateTime? selectedDateTo;
  final ValueChanged<DateTime?> onDateFromChanged;
  final ValueChanged<DateTime?> onDateToChanged;
  final VoidCallback onDatesCleared;
  final DateFormat formatter;

  @override
  Widget build(BuildContext context) {
    return staffProfitAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          const Center(child: Text('Ошибка загрузки данных о прибыли')),
      data: (profitData) {
        final breakdown = profitData['breakdown'] as List<dynamic>? ?? [];

        // Фильтруем breakdown по датам
        List<dynamic> filteredBreakdown = breakdown;
        if (selectedDateFrom != null || selectedDateTo != null) {
          filteredBreakdown = breakdown.where((item) {
            final dateTime = item['date_time'] as String?;
            if (dateTime == null || dateTime.isEmpty) {
              return false;
            }
            try {
              final date = DateTime.parse(dateTime);
              final dateOnly = DateTime(date.year, date.month, date.day);

              if (selectedDateFrom != null) {
                final fromDate = DateTime(selectedDateFrom!.year,
                    selectedDateFrom!.month, selectedDateFrom!.day);
                if (dateOnly.isBefore(fromDate)) {
                  return false;
                }
              }
              if (selectedDateTo != null) {
                final toDate = DateTime(selectedDateTo!.year,
                        selectedDateTo!.month, selectedDateTo!.day)
                    .add(const Duration(days: 1));
                if (dateOnly
                    .isAfter(toDate.subtract(const Duration(seconds: 1)))) {
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
        double filteredTotalProfit = filteredBreakdown.fold<double>(
          0.0,
          (sum, item) => sum + ((item['profit'] as num?)?.toDouble() ?? 0.0),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Фильтр по датам
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
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
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                selectedDateFrom != null
                                    ? DateFormat('dd.MM.yyyy', 'ru_RU')
                                        .format(selectedDateFrom!)
                                    : 'От',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      selectedDateFrom ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  onDateFromChanged(picked);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 18),
                              label: Text(
                                selectedDateTo != null
                                    ? DateFormat('dd.MM.yyyy', 'ru_RU')
                                        .format(selectedDateTo!)
                                    : 'До',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDateTo ?? DateTime.now(),
                                  firstDate: selectedDateFrom ?? DateTime(2020),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  onDateToChanged(picked);
                                }
                              },
                            ),
                          ),
                          if (selectedDateFrom != null ||
                              selectedDateTo != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: onDatesCleared,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Общая прибыль',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (selectedDateFrom != null || selectedDateTo != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          selectedDateFrom != null && selectedDateTo != null
                              ? '${DateFormat('dd.MM.yyyy', 'ru_RU').format(selectedDateFrom!)} - ${DateFormat('dd.MM.yyyy', 'ru_RU').format(selectedDateTo!)}'
                              : selectedDateFrom != null
                                  ? 'С ${DateFormat('dd.MM.yyyy', 'ru_RU').format(selectedDateFrom!)}'
                                  : 'До ${DateFormat('dd.MM.yyyy', 'ru_RU').format(selectedDateTo!)}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade700,
                                  ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${filteredTotalProfit.toStringAsFixed(2)} ₽',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ],
                ),
              ),
              if (filteredBreakdown.isNotEmpty) ...[
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('Детализация прибыли'),
                  children: [
                    ...filteredBreakdown.map((item) {
                      final excursionTitle =
                          item['excursion_title'] as String? ?? '';
                      final profit =
                          (item['profit'] as num?)?.toDouble() ?? 0.0;
                      final passengerCount =
                          item['passenger_count'] as int? ?? 0;
                      final dateTime = item['date_time'] as String?;
                      DateTime? date;
                      if (dateTime != null) {
                        try {
                          date = DateTime.parse(dateTime);
                        } catch (_) {}
                      }
                      return ListTile(
                        title: Text(excursionTitle),
                        subtitle:
                            date != null ? Text(formatter.format(date)) : null,
                        trailing: Text(
                          '${profit.toStringAsFixed(2)} ₽',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        leading: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people, size: 20),
                            Text(
                              '$passengerCount',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ProfitDetails extends StatelessWidget {
  const _ProfitDetails({
    required this.excursionId,
    required this.excursionDate,
    required this.profitData,
  });

  final int excursionId;
  final DateTime excursionDate;
  final Map<String, dynamic>? profitData;

  @override
  Widget build(BuildContext context) {
    if (profitData == null) {
      return const SizedBox.shrink();
    }

    final breakdown = profitData!['breakdown'] as List<dynamic>? ?? [];
    // Ищем запись не только по excursion_id, но и по дате экскурсии
    // Для одной экскурсии может быть несколько записей (по разным датам)
    final item = breakdown.firstWhere(
      (e) {
        final eId = e['excursion_id'] as int?;
        if (eId != excursionId) return false;

        // Проверяем дату
        final dateTimeStr = e['date_time'] as String?;
        if (dateTimeStr == null || dateTimeStr.isEmpty) return false;

        try {
          final itemDate = DateTime.parse(dateTimeStr);
          // Сравниваем дату и время (без секунд и миллисекунд)
          final excursionDateOnly = DateTime(
            excursionDate.year,
            excursionDate.month,
            excursionDate.day,
            excursionDate.hour,
            excursionDate.minute,
          );
          final itemDateOnly = DateTime(
            itemDate.year,
            itemDate.month,
            itemDate.day,
            itemDate.hour,
            itemDate.minute,
          );
          return excursionDateOnly == itemDateOnly;
        } catch (e) {
          return false;
        }
      },
      orElse: () => null,
    );

    if (item == null) {
      return const SizedBox.shrink();
    }

    final profit = (item['profit'] as num?)?.toDouble() ?? 0.0;
    final passengerCount = item['passenger_count'] as int? ?? 0;
    final totalRevenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final passengersByType =
        item['passengers_by_type'] as Map<String, dynamic>? ?? {};
    final staffPriceInfo = item['staff_price_info'] as Map<String, dynamic>?;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Прибыль:'),
              Text(
                '${profit.toStringAsFixed(2)} ₽',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Общая выручка:'),
              Text('${totalRevenue.toStringAsFixed(2)} ₽'),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Количество пассажиров:'),
              Text('$passengerCount'),
            ],
          ),
          if (passengersByType.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Пассажиры по типам:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ...passengersByType.entries.map((entry) {
              final typeName = entry.key == 'adult'
                  ? 'Взрослый'
                  : entry.key == 'child'
                      ? 'Ребенок'
                      : entry.key;
              return Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(typeName),
                    Text('${entry.value}'),
                  ],
                ),
              );
            }),
          ],
          if (staffPriceInfo != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Информация о цене:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Цена: ${(staffPriceInfo['price'] as num?)?.toStringAsFixed(2) ?? '0.00'} ₽',
                  ),
                  if (staffPriceInfo['min_passengers'] != null ||
                      staffPriceInfo['max_passengers'] != null)
                    Text(
                      'Диапазон пассажиров: ${staffPriceInfo['min_passengers'] ?? 0} - ${staffPriceInfo['max_passengers'] ?? '∞'}',
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
