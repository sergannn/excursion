import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/bus.dart';
import '../../../data/providers.dart';

class _BusesTab extends ConsumerStatefulWidget {
  const _BusesTab();

  @override
  ConsumerState<_BusesTab> createState() => _BusesTabState();
}

class _BusesTabState extends ConsumerState<_BusesTab> {
  @override
  Widget build(BuildContext context) {
    final busesAsync = ref.watch(busesFutureProvider);

    return busesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Ошибка загрузки: $error')),
      data: (buses) {
        if (buses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.directions_bus, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Автобусы отсутствуют'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddBusDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить автобус'),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showAddBusDialog(context, ref),
            child: const Icon(Icons.add),
            tooltip: 'Добавить автобус',
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(busesFutureProvider);
              await ref.read(busesFutureProvider.future);
            },
            child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: buses.length,
            itemBuilder: (context, index) {
              final bus = buses[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Icon(
                    Icons.directions_bus,
                    color: bus.isActive ? Colors.green : Colors.grey,
                  ),
                  title: Text(
                    'Автобус №${bus.number}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (bus.model != null && bus.model!.isNotEmpty)
                        Text('Модель: ${bus.model}'),
                      Text('Вместимость: ${bus.capacity} мест'),
                      if (bus.licensePlate != null && bus.licensePlate!.isNotEmpty)
                        Text('Гос. номер: ${bus.licensePlate}'),
                      if (bus.drivers != null && bus.drivers!.isNotEmpty)
                        Text(
                          'Водитель: ${bus.drivers!.map((d) => d.name).join(", ")}',
                          style: const TextStyle(color: Colors.blue),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!bus.isActive)
                        const Chip(
                          label: Text('Неактивен'),
                          backgroundColor: Colors.grey,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditBusDialog(context, ref, bus),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        color: Colors.red,
                        onPressed: () => _showDeleteBusDialog(context, ref, bus),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (bus.drivers != null && bus.drivers!.isNotEmpty) ...[
                            const Text(
                              'Привязанные водители:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            ...bus.drivers!.map((driver) => Card(
                                  color: Colors.blue.shade50,
                                  child: ListTile(
                                    leading: const Icon(Icons.person, color: Colors.blue),
                                    title: Text(
                                      driver.name,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                    subtitle: Text(driver.email),
                                    trailing: ElevatedButton.icon(
                                      onPressed: () => _unassignDriver(context, ref, bus, driver.id),
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Отвязать'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                                )),
                            const SizedBox(height: 16),
                            const Divider(),
                          ],
                          ElevatedButton.icon(
                            onPressed: () => _showAssignDriverDialog(context, ref, bus),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Привязать водителя'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddBusDialog(BuildContext context, WidgetRef ref) async {
    final formKey = GlobalKey<FormState>();
    final numberController = TextEditingController();
    final modelController = TextEditingController();
    final capacityController = TextEditingController(text: '50');
    final licensePlateController = TextEditingController();
    bool isActive = true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Добавить автобус'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: numberController,
                    decoration: const InputDecoration(
                      labelText: 'Номер автобуса *',
                      hintText: '123 или А123БВ',
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Обязательное поле' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: modelController,
                    decoration: const InputDecoration(
                      labelText: 'Модель',
                      hintText: 'Mercedes Sprinter',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: capacityController,
                    decoration: const InputDecoration(
                      labelText: 'Вместимость *',
                      hintText: '50',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Обязательное поле';
                      final capacity = int.tryParse(value);
                      if (capacity == null || capacity < 1) {
                        return 'Введите число больше 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: licensePlateController,
                    decoration: const InputDecoration(
                      labelText: 'Гос. номер',
                      hintText: 'А123БВ 777',
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Активен'),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final repository = ref.read(busesRepositoryProvider);
                    await repository.createBus(
                      number: numberController.text,
                      model: modelController.text.isEmpty ? null : modelController.text,
                      capacity: int.parse(capacityController.text),
                      licensePlate: licensePlateController.text.isEmpty
                          ? null
                          : licensePlateController.text,
                      isActive: isActive,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ref.invalidate(busesFutureProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Автобус успешно создан'),
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
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditBusDialog(BuildContext context, WidgetRef ref, Bus bus) async {
    final formKey = GlobalKey<FormState>();
    final numberController = TextEditingController(text: bus.number);
    final modelController = TextEditingController(text: bus.model ?? '');
    final capacityController = TextEditingController(text: bus.capacity.toString());
    final licensePlateController = TextEditingController(text: bus.licensePlate ?? '');
    bool isActive = bus.isActive;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Редактировать автобус'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: numberController,
                    decoration: const InputDecoration(labelText: 'Номер автобуса *'),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Обязательное поле' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: modelController,
                    decoration: const InputDecoration(labelText: 'Модель'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: capacityController,
                    decoration: const InputDecoration(labelText: 'Вместимость *'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Обязательное поле';
                      final capacity = int.tryParse(value);
                      if (capacity == null || capacity < 1) {
                        return 'Введите число больше 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: licensePlateController,
                    decoration: const InputDecoration(labelText: 'Гос. номер'),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Активен'),
                    value: isActive,
                    onChanged: (value) => setState(() => isActive = value ?? true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    final repository = ref.read(busesRepositoryProvider);
                    await repository.updateBus(
                      bus.id,
                      number: numberController.text,
                      model: modelController.text.isEmpty ? null : modelController.text,
                      capacity: int.parse(capacityController.text),
                      licensePlate: licensePlateController.text.isEmpty
                          ? null
                          : licensePlateController.text,
                      isActive: isActive,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ref.invalidate(busesFutureProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Автобус успешно обновлен'),
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
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteBusDialog(BuildContext context, WidgetRef ref, Bus bus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить автобус?'),
        content: Text('Вы уверены, что хотите удалить автобус №${bus.number}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repository = ref.read(busesRepositoryProvider);
        await repository.deleteBus(bus.id);
        if (context.mounted) {
          ref.invalidate(busesFutureProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Автобус успешно удален'),
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
  }

  Future<void> _showAssignDriverDialog(BuildContext context, WidgetRef ref, Bus bus) async {
    // Загружаем пользователей напрямую, без watch
    List<dynamic> users;
    try {
      users = await ref.read(allUsersFutureProvider.future);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки водителей: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
      return;
    }
    
    // Фильтруем только водителей (role_id = 3)
    final drivers = users.where((u) => u.roleId == 3).toList();
    
    if (drivers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет доступных водителей'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }
      return;
    }

    int? selectedDriverId;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Выберите водителя'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: drivers.length,
              itemBuilder: (context, index) {
                final driver = drivers[index];
                final isAlreadyAssigned = bus.drivers?.any((d) => d.id == driver.id) ?? false;

                return RadioListTile<int>(
                  title: Text(driver.name),
                  subtitle: Text(driver.email),
                  value: driver.id,
                  groupValue: selectedDriverId,
                  onChanged: isAlreadyAssigned
                      ? null
                      : (value) => setState(() => selectedDriverId = value),
                  secondary: isAlreadyAssigned
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: selectedDriverId == null
                  ? null
                  : () => Navigator.of(context).pop(selectedDriverId),
              child: const Text('Привязать'),
            ),
          ],
        ),
      ),
    );

    if (result != null && context.mounted) {
      try {
        final repository = ref.read(busesRepositoryProvider);
        await repository.assignToDriver(bus.id, result);
        if (context.mounted) {
          ref.invalidate(busesFutureProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Водитель успешно привязан'),
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
  }

  Future<void> _unassignDriver(BuildContext context, WidgetRef ref, Bus bus, int driverId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отвязать водителя?'),
        content: const Text('Вы уверены, что хотите отвязать водителя от автобуса?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Отвязать'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final repository = ref.read(busesRepositoryProvider);
        await repository.unassignFromDriver(bus.id, driverId);
        if (context.mounted) {
          ref.invalidate(busesFutureProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Водитель успешно отвязан'),
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
  }
}

// Экспортируем публичный виджет
class BusesTab extends ConsumerWidget {
  const BusesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _BusesTab();
  }
}
