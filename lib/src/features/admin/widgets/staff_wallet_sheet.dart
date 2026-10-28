import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/user_summary.dart';
import '../../../data/models/booking.dart';
import '../../../data/models/wallet.dart';
import '../../../data/providers.dart';

class StaffWalletSheet extends ConsumerStatefulWidget {
  const StaffWalletSheet({super.key, required this.user});

  final UserSummary user;

  @override
  ConsumerState<StaffWalletSheet> createState() => _StaffWalletSheetState();
}

class _StaffWalletSheetState extends ConsumerState<StaffWalletSheet> {
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

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return Material(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(widget.user.email),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.all(16),
                  children: [
                    walletAsync.when(
                      loading: () => const ListTile(
                        title: Text('Баланс'),
                        trailing: CircularProgressIndicator(),
                      ),
                      error: (error, _) => ListTile(
                        title: const Text('Баланс'),
                        subtitle: Text('Ошибка: $error'),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => ref.refresh(
                            userWalletFutureProvider(widget.user.id).future,
                          ),
                        ),
                      ),
                      data: (wallet) => Card(
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
                                final lastDate = _selectedDateTo ?? DateTime(now.year, now.month, now.day);
                                
                                final picked = await showDatePicker(
                                  context: context,
                                  firstDate: firstDate,
                                  lastDate: lastDate,
                                  initialDate: _selectedDateFrom ?? DateTime(now.year, now.month, now.day),
                                );
                                
                                if (picked != null && mounted) {
                                  setState(() {
                                    _selectedDateFrom = picked;
                                    // Если дата "от" больше даты "до", сбрасываем "до"
                                    if (_selectedDateTo != null && _selectedDateFrom!.isAfter(_selectedDateTo!)) {
                                      _selectedDateTo = null;
                                    }
                                  });
                                }
                              },
                              child: Text(
                                _selectedDateFrom == null
                                    ? 'ОТ'
                                    : DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateFrom!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () async {
                                final now = DateTime.now();
                                final firstDate = _selectedDateFrom ?? DateTime(now.year - 1, 1, 1);
                                final lastDate = DateTime(now.year, now.month, now.day);
                                
                                final picked = await showDatePicker(
                                  context: context,
                                  firstDate: firstDate,
                                  lastDate: lastDate,
                                  initialDate: _selectedDateTo ?? (_selectedDateFrom ?? DateTime(now.year, now.month, now.day)),
                                );
                                
                                if (picked != null && mounted) {
                                  setState(() {
                                    _selectedDateTo = picked;
                                    // Если дата "до" меньше даты "от", сбрасываем "от"
                                    if (_selectedDateFrom != null && _selectedDateTo!.isBefore(_selectedDateFrom!)) {
                                      _selectedDateFrom = null;
                                    }
                                  });
                                }
                              },
                              child: Text(
                                _selectedDateTo == null
                                    ? 'ДО'
                                    : DateFormat('dd.MM.yyyy', 'ru_RU').format(_selectedDateTo!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    walletAsync.when(
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
                      data: (wallet) {
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
                            if (t.booking != null && t.booking!.excursion.dateTime != null) {
                              transactionDate = t.booking!.excursion.dateTime;
                            } else {
                              transactionDate = t.createdAt;
                            }
                            
                            if (startDate != null && transactionDate.isBefore(startDate.subtract(const Duration(seconds: 1)))) {
                              return false;
                            }
                            if (endDate != null && transactionDate.isAfter(endDate.add(const Duration(seconds: 1)))) {
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
                        final groupedTransactions = <DateTime, List<WalletTransactionItem>>{};
                        for (final transaction in filteredTransactions) {
                          // Используем дату экскурсии, если есть бронирование, иначе дату создания транзакции
                          DateTime transactionDate;
                          if (transaction.booking != null && transaction.booking!.excursion.dateTime != null) {
                            transactionDate = transaction.booking!.excursion.dateTime;
                          } else {
                            transactionDate = transaction.createdAt;
                          }
                          
                          final date = DateTime(
                            transactionDate.year,
                            transactionDate.month,
                            transactionDate.day,
                          );
                          groupedTransactions.putIfAbsent(date, () => []).add(transaction);
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
                              DateTime dateA = a.booking?.excursion.dateTime ?? a.createdAt;
                              DateTime dateB = b.booking?.excursion.dateTime ?? b.createdAt;
                              return dateB.compareTo(dateA);
                            });
                            final isExpanded = _expandedDates.contains(date);
                            
                            return Card(
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
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
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
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                    subtitle: Text(
                                      DateFormat('dd.MM.yyyy HH:mm').format(transaction.createdAt),
                                      style: Theme.of(context).textTheme.bodySmall,
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
                                    children: transaction.booking != null ? [
                                      ListTile(
                                        title: Text(
                                          'Бронирование',
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const SizedBox(height: 8),
                                            Text(
                                              'Экскурсия: ${transaction.booking!.excursion.title}',
                                            ),
                                            if (transaction.booking!.excursion.dateTime != null) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                'Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(transaction.booking!.excursion.dateTime)}',
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
                                    ] : [],
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
                      isSelected:
                          List.generate(2, (index) => index == _sectionIndex),
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
                              if (startDate != null && b.bookedAt.isBefore(startDate.subtract(const Duration(seconds: 1)))) {
                                return false;
                              }
                              if (endDate != null && b.bookedAt.isAfter(endDate.add(const Duration(seconds: 1)))) {
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
                          final totalSales = filteredBookings
                              .fold<double>(0, (sum, booking) => sum + booking.price);
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_selectedDateFrom != null || _selectedDateTo != null)
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
                                    (booking) => ListTile(
                                      title: Text(booking.excursion.title),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            formatter.format(
                                                booking.excursion.dateTime),
                                          ),
                                          Text(
                                            '${booking.customerName} • ${booking.customerPhone}',
                                          ),
                                          Text(booking.passengerType.label),
                                        ],
                                      ),
                                      trailing: Text(
                                        '${booking.price.toStringAsFixed(2)} ₽',
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
                              if (startDate != null && item.bookedAt.isBefore(startDate.subtract(const Duration(seconds: 1)))) {
                                return false;
                              }
                              if (endDate != null && item.bookedAt.isAfter(endDate.add(const Duration(seconds: 1)))) {
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
                          final filteredTotalsByType = <String, ({double sales, double commission})>{};
                          double filteredTotalProfit = 0;
                          
                          for (final item in filteredBreakdown) {
                            final typeKey = item.passengerType.label;
                            final current = filteredTotalsByType[typeKey] ?? (sales: 0, commission: 0);
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
                                    (_selectedDateFrom == null && _selectedDateTo == null)
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formatter.format(
                                              item.excursion.dateTime),
                                        ),
                                        Text(item.passengerType.label),
                                        Text(
                                          'Продажа: ${item.price.toStringAsFixed(2)} ₽',
                                        ),
                                      ],
                                    ),
                                    trailing: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
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
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
