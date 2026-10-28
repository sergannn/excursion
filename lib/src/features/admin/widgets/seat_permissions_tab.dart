import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/seat_permission.dart';
import '../../../data/models/excursion.dart';
import '../../../data/models/user_summary.dart';
import '../../../data/repositories/seat_permission_repository.dart';
import '../../../data/providers.dart';

class SeatPermissionsTab extends ConsumerStatefulWidget {
  const SeatPermissionsTab({super.key});

  @override
  ConsumerState<SeatPermissionsTab> createState() => _SeatPermissionsTabState();
}

class _SeatPermissionsTabState extends ConsumerState<SeatPermissionsTab> {
  int? _selectedExcursionId;
  String? _selectedDate;
  List<SeatPermission> _permissions = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      final permissions = await repo.fetchPermissions(
        excursionId: _selectedExcursionId,
        excursionDate: _selectedDate,
      );
      setState(() {
        _permissions = permissions;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка загрузки: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  Future<void> _addPermission() async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _AddPermissionDialog(),
    );

    if (result == null) return;

    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      final excursionId = result['excursion_id'] as int;
      final userId = result['user_id'] as int;
      final excursionDate = result['excursion_date'] as String;
      
      // Создаем разрешения для обоих мест (1 и 2)
      int createdCount = 0;
      for (final seatNumber in [1, 2]) {
        try {
          await repo.createPermission(
            excursionId: excursionId,
            userId: userId,
            excursionDate: excursionDate,
            seatNumber: seatNumber,
          );
          createdCount++;
        } catch (e) {
          // Если разрешение уже существует, просто пропускаем
          if (!e.toString().contains('уже существует')) {
            rethrow;
          }
        }
      }
      
      _loadPermissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(createdCount == 2 
                ? 'Разрешения для мест 1 и 2 созданы'
                : 'Создано разрешений: $createdCount из 2'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
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

  Future<void> _deletePermission(int permissionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить разрешение?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      await repo.deletePermission(permissionId);
      _loadPermissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Разрешение удалено'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Разрешения на места 1-2'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addPermission,
            tooltip: 'Добавить разрешение',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPermissions,
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissions.isEmpty
              ? const Center(child: Text('Нет разрешений'))
              : ListView.builder(
                  itemCount: _permissions.length,
                  itemBuilder: (context, index) {
                    final permission = _permissions[index];
                    return ListTile(
                      title: Text(
                        '${permission.excursion?.title ?? 'Экскурсия ${permission.excursionId}'} - Место ${permission.seatNumber}',
                      ),
                      subtitle: Text(
                        '${permission.user?.name ?? 'Пользователь ${permission.userId}'}\n'
                        '${DateFormat('dd.MM.yyyy').format(permission.excursionDate)}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _deletePermission(permission.id),
                      ),
                    );
                  },
                ),
    );
  }
}

class _AddPermissionDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddPermissionDialog> createState() => _AddPermissionDialogState();
}

class _AddPermissionDialogState extends ConsumerState<_AddPermissionDialog> {
  Excursion? _selectedExcursion;
  UserSummary? _selectedUser;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final excursionsAsync = ref.watch(excursionsFutureProvider);
    final usersAsync = ref.watch(allUsersFutureProvider);

    return AlertDialog(
      title: const Text('Добавить разрешение'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Выбор экскурсии
            const Text('Экскурсия:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            excursionsAsync.when(
              data: (excursions) => DropdownButtonFormField<Excursion>(
                value: _selectedExcursion,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Выберите экскурсию',
                ),
                items: excursions.map((excursion) {
                  final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(excursion.dateTime);
                  return DropdownMenuItem(
                    value: excursion,
                    child: Text('${excursion.title} - $dateStr'),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _selectedExcursion = value),
              ),
              loading: () => const CircularProgressIndicator(),
              error: (error, _) => Text('Ошибка: $error'),
            ),
            const SizedBox(height: 16),
            
            // Выбор пользователя (только продавцы)
            const Text('Продавец:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            usersAsync.when(
              data: (users) {
                // Фильтруем только продавцов (role_id = 2 или роль содержит "Продавец")
                final sellers = users.where((user) {
                  return user.roleId == 2 || 
                         user.roleName.toLowerCase().contains('продавец') ||
                         user.roleName.toLowerCase().contains('seller');
                }).toList();
                
                return DropdownButtonFormField<UserSummary>(
                  value: _selectedUser,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Выберите продавца',
                  ),
                  items: sellers.map((user) {
                    return DropdownMenuItem(
                      value: user,
                      child: Text('${user.name} (${user.email})'),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => _selectedUser = value),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (error, _) => Text('Ошибка: $error'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _loading || _selectedExcursion == null || 
                    _selectedUser == null
              ? null
              : () async {
                  setState(() => _loading = true);
                  try {
                    // Используем дату из выбранной экскурсии
                    final excursionDate = DateFormat('yyyy-MM-dd').format(_selectedExcursion!.dateTime);
                    Navigator.pop(context, {
                      'excursion_id': _selectedExcursion!.id,
                      'user_id': _selectedUser!.id,
                      'excursion_date': excursionDate,
                    });
                  } catch (e) {
                    setState(() => _loading = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e')),
                      );
                    }
                  }
                },
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Создать'),
        ),
      ],
    );
  }
}

