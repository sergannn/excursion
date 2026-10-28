import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/user.dart';
import '../../data/models/excursion.dart';
import '../../data/models/booking.dart';
import '../../data/models/wallet.dart';
import '../../data/repositories/bookings_repository.dart';
import '../seller/widgets/booking_dialog.dart';
import '../seller/widgets/edit_booking_dialog.dart';
import '../seller/widgets/seat_access_request_dialog.dart';
import '../../data/repositories/seat_permission_repository.dart';
import '../../data/providers.dart';
import '../auth/auth_controller.dart';
import '../common/utils/pdf_downloader.dart';
import '../../data/models/saved_ticket.dart';
import '../common/widgets/cancellation_reason_dialog.dart';
import '../admin/widgets/prices_tab.dart';
import '../common/settings_screen.dart';
import '../excursions/widgets/excursion_gallery_dialog.dart';
import 'tickets_screen.dart';
import '../../core/services/internet_connection_service.dart';

class SellerHomePage extends ConsumerStatefulWidget {
  const SellerHomePage({super.key, required this.user});

  final User user;

  @override
  ConsumerState<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends ConsumerState<SellerHomePage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _ExcursionsTab(),
      const _BookingsTab(),
      _SellerWalletTab(user: widget.user),
      const _PricesTab(),
      const _ScheduleTab(),
    ];

    // Отслеживаем статус интернета
    final internetStatusAsync = ref.watch(internetStatusProvider);
    final hasInternet = internetStatusAsync.valueOrNull ?? true;

    // Определяем цвет фона AppBar - используем персональный цвет пользователя или цвет темы
    Color? userColor;
    if (widget.user.color != null && widget.user.color!.isNotEmpty) {
      try {
        userColor = Color(
            int.parse(widget.user.color!.replaceFirst('#', ''), radix: 16) +
                0xFF000000);
      } catch (e) {
        // Если не удалось распарсить цвет, используем null
      }
    }

    final appBarColor = userColor ??
        (hasInternet ? Theme.of(context).colorScheme.primary : Colors.red);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: Colors.white, // Белый цвет для всех элементов AppBar
        title: Text(
          'Организатор экскурсии — ${widget.user.name}',
          style:
              const TextStyle(color: Colors.white), // Явно указываем белый цвет
        ),
        actions: [
          IconButton(
            color: Colors.white, // Явно указываем белый цвет для иконки
            tooltip: 'Обновить',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(excursionsFutureProvider);
              ref.invalidate(bookingsFutureProvider);
              ref.invalidate(userWalletFutureProvider(widget.user.id));
              ref.invalidate(userSalesFutureProvider(widget.user.id));
            },
          ),
        ],
      ),
      drawer: _SellerDrawer(user: widget.user),
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (value) => setState(() => _currentIndex = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map), label: 'Экскурсии'),
          NavigationDestination(
              icon: Icon(Icons.event_seat), label: 'Бронирования'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet), label: 'Кошелёк'),
          NavigationDestination(
              icon: Icon(Icons.currency_ruble), label: 'Цены'),
          NavigationDestination(
              icon: Icon(Icons.calendar_today), label: 'Расписание'),
        ],
      ),
    );
  }
}

class _ExcursionsTab extends ConsumerStatefulWidget {
  const _ExcursionsTab();

  @override
  ConsumerState<_ExcursionsTab> createState() => _ExcursionsTabState();
}

class _ExcursionsTabState extends ConsumerState<_ExcursionsTab>
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
    final authState = ref.watch(authControllerProvider);
    final user = authState.value;
    if (user == null) return const SizedBox.shrink();
    final excursionsAsync = ref.watch(excursionsFutureProvider);
    final timeFormatter = DateFormat('HH:mm');
    final dateFormatter = DateFormat('EEEE, dd MMMM yyyy', 'ru_RU');

    return excursionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorMessage(
        message: 'Не удалось загрузить экскурсии',
        onRetry: () => ref.invalidate(excursionsFutureProvider),
      ),
      data: (items) {
        // Разделяем на предстоящие и прошедшие
        final now = DateTime.now();
        final futureItems = <Excursion>[];
        final pastItems = <Excursion>[];

        for (final excursion in items) {
          // Сравниваем полную дату и время
          if (excursion.dateTime.isAfter(now)) {
            futureItems.add(excursion);
          } else {
            // Включаем все экскурсии, которые уже прошли или происходят сейчас
            pastItems.add(excursion);
          }
        }

        // Фильтруем по выбранной дате
        final filterByDate = (List<Excursion> excursions) {
          if (_selectedDate == null) return excursions;
          return excursions.where((excursion) {
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

        final filteredFutureItems = filterByDate(futureItems);
        final filteredPastItems = filterByDate(pastItems);

        // Сортируем
        filteredFutureItems.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        filteredPastItems.sort((a, b) => b.dateTime.compareTo(a.dateTime));

        // Функция для построения списка экскурсий
        Widget buildExcursionList(List<Excursion> allItems, String emptyMessage,
            {bool isPast = false}) {
          if (allItems.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyMessage),
              ),
            );
          }
          final groups = <DateTime, List<Excursion>>{};
          for (final excursion in allItems) {
            final key = DateTime(excursion.dateTime.year,
                excursion.dateTime.month, excursion.dateTime.day);
            groups.putIfAbsent(key, () => []).add(excursion);
          }
          // Для прошедших экскурсий сортируем по убыванию (самые свежие первыми)
          // Для предстоящих - по возрастанию
          final sortedDates = groups.keys.toList()
            ..sort(
                isPast ? (a, b) => b.compareTo(a) : (a, b) => a.compareTo(b));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(excursionsFutureProvider);
              await ref.read(excursionsFutureProvider.future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedDates.length,
              itemBuilder: (context, index) {
                final date = sortedDates[index];
                final dayItems = groups[date]!;
                return _ExcursionDaySection(
                  date: dateFormatter.format(date),
                  excursions: dayItems,
                  formatter: timeFormatter,
                  user: user,
                  index: index,
                );
              },
            ),
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
                    'Экскурсии',
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
                Tab(text: 'Предстоящие'),
                Tab(text: 'Прошедшие'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  buildExcursionList(
                    filteredFutureItems,
                    _selectedDate == null
                        ? 'Нет предстоящих экскурсий'
                        : 'Нет предстоящих экскурсий на выбранную дату',
                    isPast: false,
                  ),
                  buildExcursionList(
                    filteredPastItems,
                    _selectedDate == null
                        ? 'Нет прошедших экскурсий'
                        : 'Нет прошедших экскурсий на выбранную дату',
                    isPast: true,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ExcursionDaySection extends StatelessWidget {
  const _ExcursionDaySection({
    required this.date,
    required this.excursions,
    required this.formatter,
    required this.user,
    required this.index,
  });

  final String date;
  final List<Excursion> excursions;
  final DateFormat formatter;
  final User user;
  final int index;

  @override
  Widget build(BuildContext context) {
    return _ExpandableCard(
      color: index % 2 == 0 ? Colors.grey.shade50 : Colors.white,
      child: ExpansionTile(
        title: Text(
          date,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
            '${excursions.length} ${excursions.length == 1 ? 'экскурсия' : excursions.length < 5 ? 'экскурсии' : 'экскурсий'}'),
        children: [
          for (var i = 0; i < excursions.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _ExcursionTile(
                excursion: excursions[i],
                formatter: formatter,
                user: user,
                index: i,
              ),
            ),
        ],
      ),
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
      initiallyExpanded: widget.child.initiallyExpanded ?? false,
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

class _ExcursionTile extends ConsumerWidget {
  const _ExcursionTile({
    required this.excursion,
    required this.formatter,
    required this.user,
    required this.index,
  });

  final Excursion excursion;
  final DateFormat formatter;
  final User user;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Определяем, доступна ли экскурсия для бронирования
    final isAvailable = excursion.availableSeatsCount > 0 && !excursion.isPast;

    // Определяем цвет фона: внеплановые - светло-желтый, недоступные - серый, остальные - чередующийся
    Color? cardColor;
    if (!isAvailable) {
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${excursion.title} — ${formatter.format(excursion.dateTime)} • занято ${excursion.bookedSeatsCount}/${excursion.maxSeats}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 4),
                  //    Text(
                  //       'Цена (взрослый): ${excursion.priceFor('adult').toStringAsFixed(2)} ₽, Мест: ,
                  //       style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  //              fontSize: 12,
                  //      ),
                ],
              ),
            ),
            const SizedBox(width: 4),
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
            // IconButton(
            //   icon: const Icon(Icons.event_seat, size: 20),
            //       tooltip: 'Забронировать',
            //   padding: const EdgeInsets.all(8),
            //       constraints: const BoxConstraints(),
            //       onPressed: isAvailable ? () => _book(context, ref) : null,
            //       color: isAvailable
            //           ? Theme.of(context).colorScheme.primary
            //           : Colors.grey,
            //     ),
            IconButton(
              icon: const Icon(Icons.list, size: 20),
              tooltip: 'Места',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              onPressed: excursion.busSeats.isEmpty
                  ? null
                  : () => _showSeatSheet(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _book(
    BuildContext context,
    WidgetRef ref, {
    List<int>? preselectedSeats,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final stopsAsync = await ref
        .read(stopsRepositoryProvider)
        .fetchStopsForExcursion(excursion.id);
    final result = await showDialog<BookingDialogResult>(
      context: context,
      builder: (context) => BookingDialog(
        stops: stopsAsync,
        tariffs: excursion.tariffs,
        initialSeatNumbers: preselectedSeats ?? const [],
        lockSeatSelection: (preselectedSeats?.isNotEmpty ?? false),
        excursionTitle: excursion.title,
      ),
    );

    if (result == null) {
      return;
    }

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
            );

      final response =
          await ref.read(bookingsRepositoryProvider).bookSeats(payload);
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
          print(
              'Booking response: bookings count = ${response.bookings?.length ?? 0}');
          print('Booking response: bookings = ${response.bookings}');

          final allBookingIds = response.bookings
              ?.map((b) {
                final id = b['id'];
                print('Extracting booking ID: $id (type: ${id.runtimeType})');
                return id is int ? id : (id is num ? id.toInt() : null);
              })
              .whereType<int>()
              .toList();

          print(
              'Extracted booking IDs: $allBookingIds (count: ${allBookingIds?.length ?? 0})');

          // Получаем информацию о первом бронировании для сохранения метаданных
          final firstBooking = response.bookings?.first;
          SavedTicket? ticketInfo;
          if (firstBooking != null &&
              allBookingIds != null &&
              allBookingIds.isNotEmpty) {
            // Получаем данные остановки из локального списка
            final stopId = firstBooking['stop_id'] as int?;
            String stopName = 'Не указана';
            if (stopId != null) {
              try {
                final stopsAsync = await ref
                    .read(stopsRepositoryProvider)
                    .fetchStopsForExcursion(excursion.id);
                if (stopsAsync.isNotEmpty) {
                  final stop = stopsAsync.firstWhere(
                    (s) => s.id == stopId,
                    orElse: () => stopsAsync.first,
                  );
                  stopName = stop.name;
                }
              } catch (e) {
                // Игнорируем ошибку, используем значение по умолчанию
              }
            }

            // Получаем дату/время из первого бронирования
            final dateTimeStr = firstBooking['date_time'] as String?;
            String excursionDateStr;
            if (dateTimeStr != null && dateTimeStr.isNotEmpty) {
              try {
                final dateTime = DateTime.parse(dateTimeStr);
                excursionDateStr =
                    DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
              } catch (e) {
                excursionDateStr = formatter.format(excursion.dateTime);
              }
            } else {
              excursionDateStr = formatter.format(excursion.dateTime);
            }

            // Получаем имя и телефон клиента
            // В новом формате используем данные из первого места из seats
            // В старом формате используем result.customerName/customerPhone
            String customerName;
            String customerPhone;
            if (result.seats != null && result.seats!.isNotEmpty) {
              // Новый формат: берем данные из первого места
              customerName =
                  result.seats!.first.customerName ?? result.customerName;
              customerPhone =
                  result.seats!.first.customerPhone ?? result.customerPhone;
            } else {
              // Старый формат: используем общие данные
              customerName = result.customerName;
              customerPhone = result.customerPhone;
            }

            // Подсчитываем количество мест и общую сумму из всех бронирований
            final seatCount = allBookingIds.length;
            double totalAmount = 0.0;
            if (response.bookings != null) {
              for (var booking in response.bookings!) {
                final price = booking['price'];
                if (price != null) {
                  if (price is num) {
                    totalAmount += price.toDouble();
                  } else if (price is String) {
                    totalAmount += double.tryParse(price) ?? 0.0;
                  }
                }
              }
            }

            // Если сумма равна 0, пытаемся получить из тарифов
            if (totalAmount <= 0 &&
                result.seats != null &&
                result.seats!.isNotEmpty) {
              for (var seat in result.seats!) {
                final tariff = excursion.tariffs[seat.passengerType.apiValue];
                if (tariff != null) {
                  if (seat.withEntry) {
                    totalAmount += tariff.priceWithEntry ?? tariff.price ?? 0.0;
                  } else {
                    totalAmount +=
                        tariff.priceWithoutEntry ?? tariff.price ?? 0.0;
                  }
                }
              }
            }

            ticketInfo = SavedTicket(
              bookingId: bookingId,
              ticketNumber:
                  'T-${excursion.id}-$bookingId-${DateTime.now().millisecondsSinceEpoch}',
              excursionTitle: excursion.title,
              excursionDate: excursionDateStr,
              stopName: stopName,
              customerName: customerName,
              customerPhone: customerPhone,
              fileName:
                  'ticket-$bookingId-${DateTime.now().millisecondsSinceEpoch}.pdf',
              savedAt: DateTime.now(),
              seatCount: seatCount,
              totalAmount: totalAmount,
            );
          }

          // Скачиваем PDF как байты, передавая все ID бронирований
          // Убеждаемся, что allBookingIds не null и не пустой
          final idsToSend = (allBookingIds != null && allBookingIds.isNotEmpty)
              ? allBookingIds
              : [bookingId];

          print(
              'PDF download: sending bookingIds = $idsToSend (count: ${idsToSend.length})');

          final pdfBytes =
              await ref.read(bookingsRepositoryProvider).downloadTicketPdf(
                    bookingId,
                    bookingIds: idsToSend,
                  );
          // Сохраняем/отправляем PDF (на мобильных) или скачиваем (на веб)
          await PdfDownloader.saveAndSharePdf(
            pdfBytes: pdfBytes,
            filename: 'ticket-$bookingId.pdf',
            ticketInfo: ticketInfo,
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
    final selectedSeats = <int>{};

    // Загружаем разрешения для этой экскурсии и даты
    Map<String, bool>? permissions;
    final isAdmin = user.roleId == 1 || user.isSuperUser;
    if (!isAdmin) {
      try {
        final client = ref.read(apiClientProvider);
        final permissionRepo = SeatPermissionRepository(client);
        // Используем дату из excursion.dateTime (для шаблонных экскурсий это дата из schedule_by_date)
        final excursionDate =
            DateFormat('yyyy-MM-dd').format(excursion.dateTime);
        print('=== PERMISSION CHECK ===');
        print('Excursion ID: ${excursion.id}');
        print('Excursion Title: ${excursion.title}');
        print('Excursion dateTime: ${excursion.dateTime}');
        print('Formatted date: $excursionDate');
        print('User roleId: ${user.roleId}, isSuperUser: ${user.isSuperUser}');
        permissions = await permissionRepo.checkPermissions(
          excursionId: excursion.id,
          excursionDate: excursionDate,
        );
        print('API Response: ${permissions.toString()}');
        print(
            'has_permission_for_seat_1: ${permissions['has_permission_for_seat_1']}');
        print(
            'has_permission_for_seat_2: ${permissions['has_permission_for_seat_2']}');
        print('=======================');
      } catch (e) {
        // Если не удалось загрузить разрешения, считаем что их нет
        print('Error loading permissions: $e');
        permissions = {
          'has_permission_for_seat_1': false,
          'has_permission_for_seat_2': false
        };
      }
    }

    final result = await showDialog<List<int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Схема мест'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 500),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: excursion.busSeats.map((seat) {
                  final isAvailable = seat.status == 'available';
                  final isSelected = selectedSeats.contains(seat.seatNumber);
                  // Места 1 и 2 могут продавать только администраторы или пользователи с разрешением
                  final isRestrictedSeat = [1, 2].contains(seat.seatNumber);
                  // Проверяем разрешение: для админа всегда true, для продавца проверяем permissions
                  final hasPermission = isAdmin ||
                      (isRestrictedSeat &&
                          permissions != null &&
                          ((seat.seatNumber == 1 &&
                                  (permissions['has_permission_for_seat_1'] ==
                                      true)) ||
                              (seat.seatNumber == 2 &&
                                  (permissions['has_permission_for_seat_2'] ==
                                      true))));
                  final canSelect =
                      isAvailable && (!isRestrictedSeat || hasPermission);

                  // Отладочный вывод для мест 1 и 2
                  if (isRestrictedSeat) {
                    print(
                        'Seat ${seat.seatNumber}: isAvailable=$isAvailable, isAdmin=$isAdmin, hasPermission=$hasPermission, canSelect=$canSelect');
                    if (permissions != null) {
                      print('  Permissions: ${permissions.toString()}');
                    } else {
                      print('  Permissions: null');
                    }
                  }

                  final color = isSelected
                      ? Colors.blue.shade300
                      : canSelect
                          ? Colors.green.shade200
                          : isRestrictedSeat
                              ? Colors.orange.shade200
                              : Colors.red.shade200;
                  return InkWell(
                    onTap: isAvailable && canSelect
                        ? () {
                            // Обычная логика выбора
                            setState(() {
                              if (isSelected) {
                                selectedSeats.remove(seat.seatNumber);
                              } else {
                                selectedSeats.add(seat.seatNumber);
                              }
                            });
                          }
                        : isAvailable && isRestrictedSeat && !hasPermission
                            ? () async {
                                // Показываем диалог запроса доступа
                                final requestResult = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) =>
                                      SeatAccessRequestDialog(
                                    excursion: excursion,
                                    excursionDate: excursion.dateTime,
                                    seatNumber: seat.seatNumber,
                                  ),
                                );
                                // Если запрос отправлен, закрываем диалог
                                // Пользователь может открыть его снова, чтобы увидеть обновленные разрешения
                                if (requestResult == true) {
                                  Navigator.of(context).pop();
                                }
                              }
                            : null,
                    child: Chip(
                      label: Text('${seat.seatNumber}'),
                      backgroundColor: color,
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
                onPressed: () {
                  setState(() => selectedSeats.clear());
                },
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
}

class _BookingsTab extends ConsumerStatefulWidget {
  const _BookingsTab();

  @override
  ConsumerState<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<_BookingsTab>
    with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(bookingsFutureProvider);
    final formatter = DateFormat('dd.MM.yyyy HH:mm');

    return bookingsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorMessage(
        message: 'Не удалось загрузить бронирования',
        onRetry: () => ref.invalidate(bookingsFutureProvider),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return const Center(child: Text('Вы ещё не бронировали места'));
        }

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

        final dateFormatter = DateFormat('EEEE, dd MMMM yyyy', 'ru_RU');
        final timeFormatter = DateFormat('HH:mm');

        return Column(
          children: [
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
                    formatter,
                    'Нет новых бронирований',
                  ),
                  _buildBookingsList(
                    context,
                    ref,
                    sortedOldDates,
                    oldDateGroups,
                    dateFormatter,
                    timeFormatter,
                    formatter,
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
        children: sortedDates.map((date) {
          final groups = dateGroups[date]!;
          final totalBookings =
              groups.fold<int>(0, (sum, g) => sum + g.bookings.length);
          return _ExpandableCard(
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
                return _ExpandableCard(
                  useCard: false,
                  margin: EdgeInsets.zero,
                  child: ExpansionTile(
                    title: Text(group.excursion.title),
                    subtitle: Text(
                      '${timeFormatter.format(group.excursion.dateTime)} • ${group.bookings.length} место${group.bookings.length > 1 ? 'а' : ''}${group.excursion.maxSeats != null ? ' из ${group.excursion.maxSeats}' : ''}',
                    ),
                    children: group.bookings
                        .map(
                          (booking) => ListTile(
                            title: Text('Место ${booking.seat.seatNumber}'),
                            subtitle: Text(
                              [
                                booking.customerName,
                                if (booking.stop != null) booking.stop!.name,
                                if ((booking.debt ?? 0) > 0)
                                  'долг ${(booking.debt ?? 0).toStringAsFixed(0)} ₽',
                                if (booking.comment?.trim().isNotEmpty == true)
                                  booking.comment!.trim(),
                                'Бронировано: ${subFormatter.format(booking.bookedAt)}',
                              ].join(' • '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  tooltip: 'Изменить',
                                  onPressed: () => _edit(context, ref, booking),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.cancel),
                                  tooltip: 'Убрать пассажира',
                                  onPressed: () =>
                                      _cancel(context, ref, booking.id),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _cancel(
      BuildContext context, WidgetRef ref, int bookingId) async {
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
      final authState = ref.read(authControllerProvider);
      final currentUserId = authState.value?.id;
      if (currentUserId != null) {
        ref.invalidate(userWalletFutureProvider(currentUserId));
        ref.invalidate(userSalesFutureProvider(currentUserId));
      }
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

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    BookingItem booking,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final stops = await ref
          .read(stopsRepositoryProvider)
          .fetchStopsForExcursion(booking.excursion.id);
      if (!context.mounted || stops.isEmpty) return;

      final result = await showDialog<EditBookingResult>(
        context: context,
        builder: (dialogContext) => EditBookingDialog(
          booking: booking,
          stops: stops,
        ),
      );
      if (result == null) return;

      await ref.read(bookingsRepositoryProvider).updateBooking(
            bookingId: booking.id,
            customerName: result.customerName,
            customerPhone: result.customerPhone,
            debt: result.debt,
            stopId: result.stopId,
            comment: result.comment,
          );
      ref.invalidate(bookingsFutureProvider);
      ref.invalidate(excursionsFutureProvider);
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Бронирование обновлено')),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось изменить бронирование: $error')),
      );
    }
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerWalletTab extends ConsumerStatefulWidget {
  const _SellerWalletTab({required this.user});

  final User user;

  @override
  ConsumerState<_SellerWalletTab> createState() => _SellerWalletTabState();
}

class _SellerWalletTabState extends ConsumerState<_SellerWalletTab> {
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
    final formatter = DateFormat('dd.MM.yyyy HH:mm');

    return walletAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorMessage(
        message: 'Не удалось загрузить данные кошелька',
        onRetry: () {
          ref.invalidate(userWalletFutureProvider(widget.user.id));
          ref.invalidate(userSalesFutureProvider(widget.user.id));
          ref.invalidate(userProfitFutureProvider(widget.user.id));
        },
      ),
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
                                    formatter
                                        .format(booking.excursion.dateTime),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  subtitle: Text(
                                    'Продажа: ${formatter.format(booking.bookedAt)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.grey,
                                        ),
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
              ], /*
              const SizedBox(height: 24),
              Text(
                'Активные бронирования',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              bookingsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Ошибка: $error'),
                ),
                data: (groups) {
                  if (groups.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Вы ещё не бронировали места'),
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
              ),*/
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelBooking(BuildContext context, int bookingId) async {
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

class _PricesTab extends ConsumerWidget {
  const _PricesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PricesTab(canEdit: false);
  }
}

class _ScheduleTab extends ConsumerWidget {
  const _ScheduleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheduleAsync = ref.watch(scheduleFutureProvider);

    return scheduleAsync.when(
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
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ...templates.map((template) {
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
                              style: Theme.of(context).textTheme.titleSmall,
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
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
                                                fontWeight: FontWeight.w500,
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
              }),
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
                      final unscheduledExcursions = excursions
                          .where((e) => e.isUnscheduled && !e.isDeleted)
                          .toList();

                      if (unscheduledExcursions.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      // Разделяем на прошедшие и будущие
                      final pastExcursions = unscheduledExcursions
                          .where((e) => e.dateTime.isBefore(now))
                          .toList();
                      final futureExcursions = unscheduledExcursions
                          .where((e) => !e.dateTime.isBefore(now))
                          .toList();

                      // Группируем по экскурсиям (для будущих)
                      final groupedByTitleFuture = <String, List<Excursion>>{};
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
                        if (!groupedByTitlePast.containsKey(excursion.title)) {
                          groupedByTitlePast[excursion.title] = [];
                        }
                        groupedByTitlePast[excursion.title]!.add(excursion);
                      }

                      return Card(
                        margin: const EdgeInsets.fromLTRB(0, 0, 0, 16),
                        color: Colors.amber.shade50,
                        child: ExpansionTile(
                          leading:
                              const Icon(Icons.event_busy, color: Colors.amber),
                          title: const Text(
                            'Внеплановые',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                              '${futureExcursions.length} ${futureExcursions.length == 1 ? 'экскурсия' : futureExcursions.length < 5 ? 'экскурсии' : 'экскурсий'}${pastExcursions.isNotEmpty ? ' (${pastExcursions.length} прошедших)' : ''}'),
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
                                dates.sort(
                                    (a, b) => a.dateTime.compareTo(b.dateTime));

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
    );
  }
}

class _SellerDrawer extends ConsumerWidget {
  const _SellerDrawer({required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  'Организатор экскурсии',
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
            leading: const Icon(Icons.confirmation_number),
            title: const Text('Билеты'),
            subtitle: const Text('Сохраненные билеты'),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const TicketsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Настройки'),
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
}
