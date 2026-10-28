import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/excursion.dart';
import '../../../data/providers.dart';

class PricesTab extends ConsumerWidget {
  const PricesTab({super.key, this.canEdit = true});

  final bool canEdit;

  static const _typeLabels = <String, String>{
    'adult': 'Взрослый',
    'child': 'Детский',
    'senior': 'Пенсионер',
    'disabled': 'Инвалид',
    'special': 'Спеццена',
    'concession': 'Льготный',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final excursionsAsync = ref.watch(excursionsFutureProvider);

    return excursionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Не удалось загрузить: $error')),
      data: (excursions) {
        if (excursions.isEmpty) {
          return const Center(child: Text('Экскурсии отсутствуют'));
        }

        // Убираем дубликаты по названию экскурсии
        final uniqueExcursions = <String, Excursion>{};
        for (final excursion in excursions) {
          if (!uniqueExcursions.containsKey(excursion.title)) {
            uniqueExcursions[excursion.title] = excursion;
          }
        }
        final uniqueList = uniqueExcursions.values.toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(excursionsFutureProvider);
            await ref.read(excursionsFutureProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: uniqueList.length,
            itemBuilder: (context, index) {
              final excursion = uniqueList[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: const Icon(Icons.currency_ruble),
                  title: Text(
                    excursion.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text(
                    excursion.description.isNotEmpty
                        ? excursion.description
                        : 'Описание отсутствует',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ...['adult', 'child', 'senior', 'disabled', 'special', 'concession'].map(
                            (typeKey) {
                              final label = _typeLabels[typeKey] ?? typeKey;
                              final tariff = excursion.tariffs[typeKey];
                              final priceWithout = tariff?.priceWithoutEntry ??
                                  tariff?.price ??
                                  0;
                              final priceWith =
                                  tariff?.priceWithEntry ?? tariff?.price ?? 0;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Без входа: ${priceWithout.toStringAsFixed(2)} ₽',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                          Text(
                                            'Входной билет: ${priceWith.toStringAsFixed(2)} ₽',
                                            style:
                                                const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          // Цены для персонала (только для админов)
                          if (canEdit && excursion.staffPrices.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const Text(
                              'Цены для персонала',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...excursion.staffPrices.map((staffPrice) {
                              final staffTypeLabel =
                                  staffPrice.staffType == 'driver'
                                      ? 'Водитель'
                                      : 'Экскурсовод';
                              final rangeLabel = staffPrice.maxPassengers !=
                                      null
                                  ? '${staffPrice.minPassengers}-${staffPrice.maxPassengers} пассажиров'
                                  : 'от ${staffPrice.minPassengers} пассажиров';
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$staffTypeLabel ($rangeLabel)',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    Text(
                                      '${staffPrice.price.toStringAsFixed(2)} ₽',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          if (canEdit) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.edit),
                                label: const Text('Изменить цены'),
                                onPressed: () async {
                                  final updated = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => PriceEditDialog(
                                      excursion: excursion,
                                    ),
                                  );

                                  if (updated == true) {
                                    ref.invalidate(excursionsFutureProvider);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Цены для «${excursion.title}» обновлены',
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          margin: const EdgeInsets.all(16),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class PriceEditDialog extends ConsumerStatefulWidget {
  const PriceEditDialog({super.key, required this.excursion});

  final Excursion excursion;

  @override
  ConsumerState<PriceEditDialog> createState() => _PriceEditDialogState();
}

class _PriceEditDialogState extends ConsumerState<PriceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _priceControllers;
  late final Map<String, TextEditingController> _priceWithoutEntryControllers;
  late final Map<String, TextEditingController> _priceWithEntryControllers;

  // Контроллеры для цен персонала
  final List<_StaffPriceRow> _staffPriceRows = [];

  bool _isSubmitting = false;
  String? _errorMessage;

  static const _typeOrder = ['adult', 'child', 'senior', 'disabled', 'special', 'concession'];
  static const _labels = <String, String>{
    'adult': 'Взрослый',
    'child': 'Детский',
    'senior': 'Пенсионер',
    'disabled': 'Инвалид',
    'special': 'Спеццена',
    'concession': 'Льготный',
  };

  @override
  void initState() {
    super.initState();
    _priceControllers = {};
    _priceWithoutEntryControllers = {};
    _priceWithEntryControllers = {};

    for (final type in _typeOrder) {
      final tariff = widget.excursion.tariffs[type];
      _priceControllers[type] = TextEditingController(
        text: widget.excursion.priceFor(type).toStringAsFixed(2),
      );
      _priceWithoutEntryControllers[type] = TextEditingController(
        text: (tariff?.priceWithoutEntry ?? tariff?.price ?? 0)
            .toStringAsFixed(2),
      );
      _priceWithEntryControllers[type] = TextEditingController(
        text: (tariff?.priceWithEntry ?? tariff?.price ?? 0).toStringAsFixed(2),
      );
    }

    // Инициализируем цены персонала
    for (final staffPrice in widget.excursion.staffPrices) {
      _staffPriceRows.add(_StaffPriceRow(
        staffType: staffPrice.staffType,
        minPassengers: staffPrice.minPassengers,
        maxPassengers: staffPrice.maxPassengers,
        price: staffPrice.price,
      ));
    }

    // Добавляем пустые строки для водителя и экскурсовода, если их нет
    if (!_staffPriceRows.any((row) => row.staffType == 'driver')) {
      _staffPriceRows.add(_StaffPriceRow(staffType: 'driver'));
    }
    if (!_staffPriceRows.any((row) => row.staffType == 'guide')) {
      _staffPriceRows.add(_StaffPriceRow(staffType: 'guide'));
    }
  }

  @override
  void dispose() {
    for (final controller in _priceControllers.values) {
      controller.dispose();
    }
    for (final controller in _priceWithoutEntryControllers.values) {
      controller.dispose();
    }
    for (final controller in _priceWithEntryControllers.values) {
      controller.dispose();
    }
    for (final row in _staffPriceRows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Цены для «${widget.excursion.title}»'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in _typeOrder)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _labels[type]!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceControllers[type],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Основная цена',
                          suffixText: '₽',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите цену';
                          }
                          final normalized = value.replaceAll(',', '.');
                          final parsed = double.tryParse(normalized);
                          if (parsed == null || parsed < 0) {
                            return 'Некорректная цена';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceWithoutEntryControllers[type],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Цена без входа',
                          suffixText: '₽',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите цену';
                          }
                          final normalized = value.replaceAll(',', '.');
                          final parsed = double.tryParse(normalized);
                          if (parsed == null || parsed < 0) {
                            return 'Некорректная цена';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _priceWithEntryControllers[type],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Цена со входом',
                          suffixText: '₽',
                          isDense: true,
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Введите цену';
                          }
                          final normalized = value.replaceAll(',', '.');
                          final parsed = double.tryParse(normalized);
                          if (parsed == null || parsed < 0) {
                            return 'Некорректная цена';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              const Divider(),
              const Text(
                'Цены для персонала (зависит от количества пассажиров)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ..._staffPriceRows.map((row) => _buildStaffPriceRow(row)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить диапазон'),
                onPressed: () {
                  setState(() {
                    _staffPriceRows.add(_StaffPriceRow(staffType: 'driver'));
                  });
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _buildStaffPriceRow(_StaffPriceRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: DropdownButtonFormField<String>(
              value: row.staffType,
              decoration: const InputDecoration(
                labelText: 'Тип',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              ),
              style: const TextStyle(fontSize: 12),
              items: const [
                DropdownMenuItem(value: 'driver', child: Text('Вод')),
                DropdownMenuItem(value: 'guide', child: Text('Экс')),
              ],
              onChanged: (value) {
                setState(() {
                  row.staffType = value ?? 'driver';
                });
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 55,
            child: TextFormField(
              controller: row.minPassengersController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'От',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Обязательно';
                }
                final parsed = int.tryParse(value);
                if (parsed == null || parsed < 0) {
                  return 'Число ≥ 0';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 55,
            child: TextFormField(
              controller: row.maxPassengersController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                labelText: 'До',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final parsed = int.tryParse(value);
                  if (parsed == null || parsed < 0) {
                    return 'Число ≥ 0';
                  }
                  final min =
                      int.tryParse(row.minPassengersController.text) ?? 0;
                  if (parsed < min) {
                    return 'Должно быть ≥ $min';
                  }
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: row.priceController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                labelText: 'Цена',
                suffixText: '₽',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Обязательно';
                }
                final normalized = value.replaceAll(',', '.');
                final parsed = double.tryParse(normalized);
                if (parsed == null || parsed < 0) {
                  return 'Число ≥ 0';
                }
                return null;
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              setState(() {
                _staffPriceRows.remove(row);
                row.dispose();
              });
            },
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final prices = <String, Map<String, dynamic>>{};
    for (final type in _typeOrder) {
      final normalizedPrice =
          _priceControllers[type]!.text.replaceAll(',', '.');
      final normalizedWithout =
          _priceWithoutEntryControllers[type]!.text.replaceAll(',', '.');
      final normalizedWith =
          _priceWithEntryControllers[type]!.text.replaceAll(',', '.');

      final tariff = widget.excursion.tariffs[type];
      prices[type] = {
        'price': double.parse(normalizedPrice),
        'price_without_entry': double.parse(normalizedWithout),
        'price_with_entry': double.parse(normalizedWith),
        'seller_commission_percent': tariff?.sellerCommissionPercent ?? 10.0,
        'partner_commission_percent': tariff?.partnerCommissionPercent ?? 10.0,
      };
    }

    // Подготавливаем цены персонала
    final staffPrices = <Map<String, dynamic>>[];
    for (final row in _staffPriceRows) {
      if (row.priceController.text.trim().isEmpty) {
        continue; // Пропускаем пустые строки
      }
      final minPassengers = int.parse(row.minPassengersController.text);
      final maxPassengersText = row.maxPassengersController.text.trim();
      staffPrices.add({
        'staff_type': row.staffType,
        'min_passengers': minPassengers,
        'max_passengers':
            maxPassengersText.isEmpty ? null : int.parse(maxPassengersText),
        'price': double.parse(row.priceController.text.replaceAll(',', '.')),
      });
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // Обновляем цены пассажиров
      await ref.read(excursionsRepositoryProvider).updateTariffs(
            excursionId: widget.excursion.id,
            prices: prices,
            currentExcursion: widget.excursion,
          );

      // Обновляем цены персонала
      if (staffPrices.isNotEmpty) {
        await ref.read(excursionsRepositoryProvider).updateStaffPrices(
              excursionId: widget.excursion.id,
              staffPrices: staffPrices,
            );
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = '$error';
      });
    }
  }
}

class _StaffPriceRow {
  _StaffPriceRow({
    String? staffType,
    int? minPassengers,
    int? maxPassengers,
    double? price,
  })  : staffType = staffType ?? 'driver',
        staffTypeController =
            TextEditingController(text: staffType ?? 'driver'),
        minPassengersController = TextEditingController(
          text: (minPassengers ?? 0).toString(),
        ),
        maxPassengersController = TextEditingController(
          text: maxPassengers?.toString() ?? '',
        ),
        priceController = TextEditingController(
          text: (price ?? 0.0).toStringAsFixed(2),
        );

  String staffType;
  final TextEditingController staffTypeController;
  final TextEditingController minPassengersController;
  final TextEditingController maxPassengersController;
  final TextEditingController priceController;

  void dispose() {
    staffTypeController.dispose();
    minPassengersController.dispose();
    maxPassengersController.dispose();
    priceController.dispose();
  }
}
