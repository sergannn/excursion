import 'package:flutter/material.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/stop.dart';
import '../../../data/models/excursion.dart';
import '../../../data/models/user_summary.dart';
import '../../../data/repositories/bookings_repository.dart';

class BookingDialog extends StatefulWidget {
  const BookingDialog({
    super.key,
    required this.stops,
    required this.tariffs,
    this.initialSeatNumbers = const [],
    this.lockSeatSelection = false,
    this.sellers, // Список продавцов для выбора (только для админов)
    this.currentUserId, // ID текущего пользователя (для админов)
    this.excursionTitle, // Название экскурсии для отображения в заголовке
  });

  final List<Stop> stops;
  final Map<String, ExcursionTariff> tariffs;
  final List<int> initialSeatNumbers;
  final bool lockSeatSelection;
  final List<UserSummary>? sellers; // Список продавцов/партнеров для выбора
  final int? currentUserId; // ID текущего пользователя
  final String? excursionTitle; // Название экскурсии

  @override
  State<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<BookingDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _seatsController = TextEditingController();
  late TabController _tabController;

  int? _stopId;
  Stop? _selectedStop;
  late final List<int> _seatNumbers;
  int? _selectedSellerId; // Выбранный продавец/партнер (для админов)

  // Данные для каждого места: номер места -> данные пассажира
  final Map<int, _SeatPassengerData> _seatData = {};

  @override
  void initState() {
    super.initState();
    _seatNumbers = List<int>.from(widget.initialSeatNumbers);
    if (_seatNumbers.isNotEmpty) {
      _seatsController.text = _seatNumbers.join(', ');
      // Инициализируем данные для каждого места
      for (final seatNum in _seatNumbers) {
        _seatData[seatNum] = _SeatPassengerData();
      }
    }
    if (widget.stops.isNotEmpty) {
      _selectedStop = widget.stops.first;
      _stopId = _selectedStop!.id;
    }
    // По умолчанию выбираем текущего пользователя (если это админ)
    if (widget.currentUserId != null) {
      _selectedSellerId = widget.currentUserId;
    }
    _tabController = TabController(
      length: _seatNumbers.isEmpty ? 1 : _seatNumbers.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _seatsController.dispose();
    _tabController.dispose();
    for (final data in _seatData.values) {
      data.nameController.dispose();
      data.phoneController.dispose();
      data.manualPriceController.dispose();
      data.debtController.dispose();
      data.commentController.dispose();
    }
    super.dispose();
  }

  void _updateSeats() {
    final seats = _parseSeatNumbers(_seatsController.text.trim());
    setState(() {
      // Удаляем данные для мест, которых больше нет
      _seatData.removeWhere((seatNum, _) => !seats.contains(seatNum));
      // Добавляем данные для новых мест
      for (final seatNum in seats) {
        _seatData.putIfAbsent(seatNum, () => _SeatPassengerData());
      }
      _seatNumbers.clear();
      _seatNumbers.addAll(seats);
      // Обновляем TabController
      final oldLength = _tabController.length;
      final newLength = seats.isEmpty ? 1 : seats.length;
      if (oldLength != newLength) {
        _tabController.dispose();
        _tabController = TabController(length: newLength, vsync: this);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSeats = _seatNumbers.isNotEmpty;

    return AlertDialog(
      title: Text(widget.excursionTitle ?? 'Новое бронирование'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Поле для ввода мест (если не заблокировано)
                if (!widget.lockSeatSelection) ...[
                  TextFormField(
                    controller: _seatsController,
                    decoration: const InputDecoration(
                      labelText: 'Места',
                      hintText: 'Например: 3,5,7 или 3-7',
                      helperText:
                          'Можно указать несколько мест через запятую (3,5,7) или диапазон (3-7)',
                    ),
                    keyboardType: TextInputType.text,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Введите номера мест';
                      }
                      final seats = _parseSeatNumbers(value.trim());
                      if (seats.isEmpty) {
                        return 'Введите корректные номера мест';
                      }
                      if (seats.any((s) => s <= 0 || s > 100)) {
                        return 'Номера мест должны быть от 1 до 100';
                      }
                      return null;
                    },
                    onChanged: (_) => _updateSeats(),
                  ),
                  const SizedBox(height: 16),
                ],

                // Табы для каждого места
                if (hasSeats) ...[
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabs: _seatNumbers
                        .map((seatNum) => Tab(text: 'Место $seatNum'))
                        .toList(),
                  ),
                  SizedBox(
                    height: 400,
                    child: TabBarView(
                      controller: _tabController,
                      children: _seatNumbers.map((seatNum) {
                        return _buildSeatTab(seatNum);
                      }).toList(),
                    ),
                  ),
                ] else ...[
                  // Если мест нет, показываем сообщение
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('Введите номера мест для бронирования'),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Выбор продавца/партнера (только для админов)
                if (widget.sellers != null && widget.sellers!.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: _selectedSellerId,
                    decoration: const InputDecoration(
                      labelText: 'Бронировать от лица',
                      helperText: 'Выберите продавца, партнера или себя',
                    ),
                    items: [
                      // Опция "Я сам" (текущий пользователь)
                      if (widget.currentUserId != null)
                        DropdownMenuItem(
                          value: widget.currentUserId,
                          child: const Text('Я сам (администратор)'),
                        ),
                      // Список продавцов и партнеров
                      ...widget.sellers!.map(
                        (seller) {
                          final roleLabel = seller.roleName.trim().isEmpty
                              ? null
                              : seller.roleName;
                          final label = roleLabel == null
                              ? seller.name
                              : '${seller.name} ($roleLabel)';

                          return DropdownMenuItem(
                            value: seller.id,
                            child: Text(label),
                          );
                        },
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSellerId = value;
                      });
                    },
                    validator: (value) =>
                        value == null ? 'Выберите продавца или партнера' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Общая остановка для всех мест
                DropdownButtonFormField<int>(
                  value: _stopId,
                  decoration: const InputDecoration(labelText: 'Остановка'),
                  items: widget.stops
                      .map(
                        (stop) => DropdownMenuItem(
                          value: stop.id,
                          child: Text(stop.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _stopId = value;
                      _selectedStop =
                          widget.stops.firstWhere((stop) => stop.id == value);
                    });
                  },
                  validator: (value) =>
                      value == null ? 'Выберите остановку' : null,
                ),

                // Итоговая сумма
                if (hasSeats) ...[
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      double total = 0;
                      for (final seatNum in _seatNumbers) {
                        final data = _seatData[seatNum]!;
                        final manualPrice = data.manualPrice;
                        if (data.useManualPrice && manualPrice != null) {
                          total += manualPrice;
                          continue;
                        }
                        final tariff =
                            widget.tariffs[data.passengerType.apiValue];
                        if (tariff != null) {
                          final price = data.withEntry
                              ? (tariff.priceWithEntry ?? tariff.price)
                              : (tariff.priceWithoutEntry ?? tariff.price);
                          total += price;
                        }
                      }
                      return Text(
                        'Итого: ${total.toStringAsFixed(2)} ₽',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    },
                  ),
                ],

                // Кнопки действий (внутри скроллируемого контента)
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_seatNumbers.length > 1)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Копировать для всех'),
                        onPressed: () =>
                            _copyToAllSeats(_seatNumbers[_tabController.index]),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    FilledButton(
                      onPressed: () {
                        if (!(_formKey.currentState?.validate() ?? false)) {
                          return;
                        }

                        if (!hasSeats) {
                          final rootContext =
                              Navigator.of(context, rootNavigator: true)
                                  .context;
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            const SnackBar(
                              content: Text('Введите номера мест'),
                              behavior: SnackBarBehavior.floating,
                              margin: EdgeInsets.all(16),
                            ),
                          );
                          return;
                        }

                        // Проверяем, что для всех мест заполнены данные
                        for (final seatNum in _seatNumbers) {
                          final data = _seatData[seatNum]!;
                          if (data.nameController.text.trim().isEmpty) {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Введите имя пассажира для места $seatNum'),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }
                          if (data.phoneController.text.trim().isEmpty) {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Введите телефон пассажира для места $seatNum'),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }
                          if (data.useManualPrice) {
                            final manualPrice = data.manualPrice;
                            if (manualPrice == null) {
                              final rootContext =
                                  Navigator.of(context, rootNavigator: true)
                                      .context;
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Введите корректную цену для места $seatNum'),
                                  behavior: SnackBarBehavior.floating,
                                  margin: const EdgeInsets.all(16),
                                ),
                              );
                              return;
                            }
                          }
                          final debt = data.debt;
                          final seatPrice = data.effectivePrice(widget.tariffs);
                          if (debt != null && debt < 0) {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Долг для места $seatNum не может быть отрицательным'),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }
                          if (debt != null &&
                              seatPrice != null &&
                              debt > seatPrice) {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Долг для места $seatNum не должен быть больше цены'),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }
                          final tariff =
                              widget.tariffs[data.passengerType.apiValue];
                          if (!data.useManualPrice && tariff == null) {
                            final rootContext =
                                Navigator.of(context, rootNavigator: true)
                                    .context;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Цена для типа "${data.passengerType.label}" на месте $seatNum не настроена',
                                ),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                            return;
                          }
                        }

                        // Собираем все места с данными
                        final seats = _seatNumbers.map((seatNum) {
                          final data = _seatData[seatNum]!;
                          return SeatBooking(
                            seatNumber: seatNum,
                            passengerType: data.passengerType,
                            withEntry: data.withEntry,
                            price:
                                data.useManualPrice ? data.manualPrice : null,
                            debt: data.debt,
                            customerName: data.nameController.text.trim(),
                            customerPhone: data.phoneController.text.trim(),
                            comment: data.commentController.text.trim(),
                          );
                        }).toList();

                        Navigator.of(context).pop(
                          BookingDialogResult(
                            seats: seats,
                            seatNumbers: _seatNumbers,
                            pricePerSeat: 0, // Не используется в новом формате
                            customerName: _seatData[_seatNumbers.first]!
                                .nameController
                                .text
                                .trim(),
                            customerPhone: _seatData[_seatNumbers.first]!
                                .phoneController
                                .text
                                .trim(),
                            passengerType:
                                _seatData[_seatNumbers.first]!.passengerType,
                            stop: _selectedStop!,
                            bookedById:
                                _selectedSellerId, // ID выбранного продавца (для админов)
                          ),
                        );
                      },
                      child: const Text('Сохранить'),
                    ),
                  ],
                ),
                const SizedBox(
                    height: 8), // Небольшой отступ снизу для удобства
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeatTab(int seatNum) {
    final data = _seatData[seatNum]!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          TextFormField(
            controller: data.nameController,
            decoration: const InputDecoration(labelText: 'Имя пассажира'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите имя';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: data.phoneController,
            decoration: const InputDecoration(labelText: 'Телефон пассажира'),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Введите телефон';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          // Заголовок "Тип пассажира"
          const Text(
            'Тип пассажира',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          // Категория "Без входных"
          _buildCategoryHeader('Без входных'),
          const SizedBox(height: 8),
          _buildPassengerTypeOption(
            data,
            PassengerType.adult,
            'Взрослый',
            false,
          ),
          const SizedBox(height: 4),
          _buildPassengerTypeOption(
            data,
            PassengerType.concession,
            'Льготный',
            false,
          ),
          const SizedBox(height: 16),
          // Категория "Со входными"
          _buildCategoryHeader('Со входными'),
          const SizedBox(height: 8),
          _buildPassengerTypeOption(
            data,
            PassengerType.adult,
            'Взрослый',
            true,
          ),
          const SizedBox(height: 4),
          _buildPassengerTypeOption(
            data,
            PassengerType.child,
            'Детский',
            true,
          ),
          const SizedBox(height: 4),
          _buildPassengerTypeOption(
            data,
            PassengerType.senior,
            'Пенсионер',
            true,
          ),
          const SizedBox(height: 4),
          _buildPassengerTypeOption(
            data,
            PassengerType.disabled,
            'Инвалид',
            true,
          ),
          const SizedBox(height: 16),
          // Спеццена отдельно
          _buildPassengerTypeOption(
            data,
            PassengerType.special,
            'Спеццена',
            false,
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Своя цена'),
            subtitle: const Text('Продавец вводит любую цену вручную'),
            value: data.useManualPrice,
            onChanged: (value) {
              setState(() {
                data.useManualPrice = value;
                if (!value) {
                  data.manualPriceController.clear();
                }
              });
            },
          ),
          if (data.useManualPrice) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: data.manualPriceController,
              decoration: const InputDecoration(
                labelText: 'Цена вручную',
                hintText: 'Например, 1350',
                suffixText: '₽',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                setState(() {});
              },
              validator: (value) {
                if (!data.useManualPrice) {
                  return null;
                }
                final normalized = value?.trim().replaceAll(',', '.');
                final parsed = normalized == null || normalized.isEmpty
                    ? null
                    : double.tryParse(normalized);
                if (parsed == null || parsed < 0) {
                  return 'Введите корректную цену';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: data.debtController,
            decoration: const InputDecoration(
              labelText: 'Долг',
              hintText: 'Например, 500',
              suffixText: '₽',
              helperText: 'Если турист оплатил не всю сумму',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              setState(() {});
            },
            validator: (value) {
              final normalized = value?.trim().replaceAll(',', '.');
              if (normalized == null || normalized.isEmpty) {
                return null;
              }
              final parsed = double.tryParse(normalized);
              if (parsed == null || parsed < 0) {
                return 'Введите корректную сумму долга';
              }
              final seatPrice = data.effectivePrice(widget.tariffs);
              if (seatPrice != null && parsed > seatPrice) {
                return 'Долг не должен быть больше цены';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: data.commentController,
            decoration: const InputDecoration(
              labelText: 'Комментарий к месту',
              hintText: 'Например: посадить ближе, длинные ноги, коляска',
            ),
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final effectivePrice = data.effectivePrice(widget.tariffs);
              if (data.useManualPrice && effectivePrice == null) {
                return const Text(
                  'Введите цену вручную',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }
              if (effectivePrice != null) {
                final debt = data.debt ?? 0;
                final paid = (effectivePrice - debt).clamp(0, effectivePrice);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Цена: ${effectivePrice.toStringAsFixed(2)} ₽',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (debt > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Оплачено: ${paid.toStringAsFixed(2)} ₽',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      Text(
                        'Долг: ${debt.toStringAsFixed(2)} ₽',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                );
              }
              return const Text(
                'Цена для выбранного типа не настроена',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildPassengerTypeOption(
    _SeatPassengerData data,
    PassengerType type,
    String label,
    bool requiresEntry,
  ) {
    // Проверяем, выбран ли этот тип с правильным флагом withEntry
    final isSelected =
        data.passengerType == type && data.withEntry == requiresEntry;

    return InkWell(
      onTap: () {
        setState(() {
          data.passengerType = type;
          data.withEntry = requiresEntry;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // Показываем цену
            Builder(
              builder: (context) {
                final tariff = widget.tariffs[type.apiValue];
                if (tariff != null) {
                  final price = requiresEntry
                      ? (tariff.priceWithEntry ?? tariff.price)
                      : (tariff.priceWithoutEntry ?? tariff.price);
                  return Text(
                    '${price.toStringAsFixed(2)} ₽',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Копирует данные из указанного места на все остальные места
  void _copyToAllSeats(int sourceSeatNum) {
    final sourceData = _seatData[sourceSeatNum]!;

    setState(() {
      for (final seatNum in _seatNumbers) {
        if (seatNum != sourceSeatNum) {
          final targetData = _seatData[seatNum]!;
          // Копируем имя
          targetData.nameController.text = sourceData.nameController.text;
          // Копируем телефон
          targetData.phoneController.text = sourceData.phoneController.text;
          // Копируем тип пассажира и флаг входного билета
          targetData.passengerType = sourceData.passengerType;
          targetData.withEntry = sourceData.withEntry;
          targetData.useManualPrice = sourceData.useManualPrice;
          targetData.manualPriceController.text =
              sourceData.manualPriceController.text;
          targetData.debtController.text = sourceData.debtController.text;
          targetData.commentController.text = sourceData.commentController.text;
        }
      }
    });

    // Показываем уведомление поверх диалога
    if (mounted) {
      // Используем rootNavigator для отображения поверх диалогов
      final rootContext = Navigator.of(context, rootNavigator: true).context;
      ScaffoldMessenger.of(rootContext).showSnackBar(
        SnackBar(
          content: Text(
            'Данные из места $sourceSeatNum скопированы на все остальные места',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  /// Парсит строку с номерами мест (поддерживает запятые и диапазоны)
  List<int> _parseSeatNumbers(String input) {
    if (input.isEmpty) return [];

    final result = <int>{};
    final parts = input.split(',');

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.contains('-')) {
        // Диапазон: 3-7
        final rangeParts = trimmed.split('-');
        if (rangeParts.length == 2) {
          final start = int.tryParse(rangeParts[0].trim());
          final end = int.tryParse(rangeParts[1].trim());
          if (start != null && end != null && start <= end) {
            for (int i = start; i <= end; i++) {
              result.add(i);
            }
          }
        }
      } else {
        // Одно число
        final number = int.tryParse(trimmed);
        if (number != null && number > 0 && number <= 100) {
          result.add(number);
        }
      }
    }

    return result.toList()..sort();
  }
}

class _SeatPassengerData {
  _SeatPassengerData()
      : nameController = TextEditingController(),
        phoneController = TextEditingController(),
        manualPriceController = TextEditingController(),
        debtController = TextEditingController(),
        commentController = TextEditingController();

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController manualPriceController;
  final TextEditingController debtController;
  final TextEditingController commentController;
  PassengerType passengerType = PassengerType.adult;
  bool withEntry =
      false; // Определяется автоматически на основе выбранной категории
  bool useManualPrice = false;

  double? get manualPrice {
    final normalized = manualPriceController.text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  double? get debt {
    final normalized = debtController.text.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  double? effectivePrice(Map<String, ExcursionTariff> tariffs) {
    if (useManualPrice) {
      return manualPrice;
    }
    final tariff = tariffs[passengerType.apiValue];
    if (tariff == null) {
      return null;
    }
    return withEntry
        ? (tariff.priceWithEntry ?? tariff.price)
        : (tariff.priceWithoutEntry ?? tariff.price);
  }
}

class BookingDialogResult {
  const BookingDialogResult({
    required this.seatNumbers,
    required this.pricePerSeat,
    required this.customerName,
    required this.customerPhone,
    required this.passengerType,
    required this.stop,
    this.seats, // Новый формат: список мест с типами
    this.bookedById, // ID продавца, от лица которого бронируем (для админов)
  });

  final List<int> seatNumbers;
  final double pricePerSeat;
  final String customerName;
  final String customerPhone;
  final PassengerType passengerType;
  final Stop stop;
  final List<SeatBooking>? seats; // Новый формат
  final int? bookedById; // ID продавца, от лица которого бронируем

  int get stopId => stop.id;
}
