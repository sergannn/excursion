import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../../data/models/user_summary.dart';
import '../../../data/providers.dart';
import '../../../core/api/api_exception.dart';
import 'staff_wallet_sheet.dart';

class UsersTab extends ConsumerStatefulWidget {
  const UsersTab({super.key, required this.currentUserId});

  final int currentUserId;

  @override
  ConsumerState<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<UsersTab>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  String _query = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersFutureProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Поиск по имени или email',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
                onPressed: () async {
                  final created = await showDialog<UserSummary?>(
                    context: context,
                    builder: (context) => const _CreateUserDialog(),
                  );
                  if (created != null && context.mounted) {
                    ref.invalidate(allUsersFutureProvider);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Пользователь "${created.name}" создан. Логин: ${created.email}',
                        ),
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(16),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Все'),
            Tab(text: 'Водители'),
            Tab(text: 'Экскурсоводы'),
            Tab(text: 'Продавцы'),
            Tab(text: 'Партнеры'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildUsersList(usersAsync, null),
              _buildUsersList(usersAsync, 3), // role_id для водителей
              _buildUsersList(usersAsync, null,
                  isGuide: true), // экскурсоводы определяются по роли
              _buildUsersList(usersAsync, 2), // role_id для продавцов
              _buildUsersList(usersAsync, 4), // role_id для партнеров
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUsersList(
    AsyncValue<List<UserSummary>> usersAsync,
    int? roleId, {
    bool isGuide = false,
  }) {
    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _UsersError(message: '$error'),
      data: (users) {
        // Фильтруем по роли или по назначениям
        List<UserSummary> filtered = users;
        if (roleId != null) {
          filtered = users.where((user) => user.roleId == roleId).toList();
        } else if (isGuide) {
          // Для экскурсоводов фильтруем по названию роли
          filtered = users.where((user) {
            final roleName = user.roleName.toLowerCase();
            return roleName.contains('экскурсовод') ||
                roleName.contains('гид') ||
                roleName.contains('guide');
          }).toList();
        }

        // Применяем поиск
        if (_query.trim().isNotEmpty) {
          final q = _query.toLowerCase();
          filtered = filtered.where((user) {
            return user.name.toLowerCase().contains(q) ||
                user.email.toLowerCase().contains(q);
          }).toList();
        }

        if (filtered.isEmpty) {
          return const Center(
            child: Text('Сотрудников пока нет'),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(allUsersFutureProvider);
            await ref.read(allUsersFutureProvider.future);
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = filtered[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: user.color != null && user.color!.isNotEmpty
                      ? (() {
                          try {
                            return Color(int.parse(user.color!.replaceFirst('#', ''), radix: 16) + 0xFF000000);
                          } catch (e) {
                            return Theme.of(context).colorScheme.primary;
                          }
                        })()
                      : Theme.of(context).colorScheme.primary,
                  child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white)),
                ),
                title: Text(user.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${user.email} • ${user.roleName}'),
                    if (user.password != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.lock, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'Пароль: ${user.password}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (user.balance > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '${user.balance.toStringAsFixed(2)} ₽',
                          style: const TextStyle(color: Colors.green),
                        ),
                      ),
                    PopupMenuButton<_UserAction>(
                      onSelected: (action) {
                        if (action == _UserAction.delete) {
                          _deleteUser(context, user);
                        } else if (action == _UserAction.setColor) {
                          _setUserColor(context, user);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _UserAction.setColor,
                          child: Text('Назначить цвет'),
                        ),
                        const PopupMenuItem(
                          value: _UserAction.delete,
                          child: Text('Удалить.'),
                        ),
                      ],
                    ),
                  ],
                ),
                onTap: () => _openWallet(context, user),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openWallet(BuildContext context, UserSummary user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StaffWalletSheet(user: user),
    );
  }

  Future<void> _deleteUser(BuildContext context, UserSummary user) async {
    if (user.id == widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нельзя удалить собственного пользователя'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить пользователя'),
        content: Text(
          'Вы уверены, что хотите удалить сотрудника "${user.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(usersRepositoryProvider).deleteUser(user.id);
      ref.invalidate(allUsersFutureProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Пользователь "${user.name}" удалён'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось удалить: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _setUserColor(BuildContext context, UserSummary user) async {
    final selectedColor = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _ColorPickerDialog(
        currentColor: user.color,
        userName: user.name,
      ),
    );

    if (selectedColor == null) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(usersRepositoryProvider).updateUserColor(
            user.id,
            selectedColor.isEmpty ? null : selectedColor,
          );
      ref.invalidate(allUsersFutureProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            selectedColor.isEmpty
                ? 'Цвет пользователя "${user.name}" удалён'
                : 'Цвет пользователя "${user.name}" обновлён',
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось обновить цвет: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

enum _UserAction { delete, setColor }

class _UsersError extends StatelessWidget {
  const _UsersError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CreateUserDialog extends ConsumerStatefulWidget {
  const _CreateUserDialog();

  @override
  ConsumerState<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends ConsumerState<_CreateUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  int? _selectedRoleId;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _passwordController.text = _generatePassword();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rolesAsync = ref.watch(userRolesFutureProvider);

    return AlertDialog(
      title: const Text('Новый сотрудник'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Имя и инициалы'),
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Введите имя'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email/логин'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите email';
                  }
                  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Некорректный email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Пароль',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Сгенерировать пароль',
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(
                              () => _passwordController.text =
                                  _generatePassword(),
                            ),
                  ),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Минимум 8 символов';
                  }
                  if (utf8.encode(value).length > 72 ||
                      RegExp(r'\s').hasMatch(value) ||
                      !RegExp(r'[a-z]').hasMatch(value) ||
                      !RegExp(r'[A-Z]').hasMatch(value) ||
                      !RegExp(r'[0-9]').hasMatch(value) ||
                      !RegExp(r'[^A-Za-z0-9\s]').hasMatch(value)) {
                    return 'Нужны A–Z, a–z, цифра и символ, без пробелов (до 72 байт)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              rolesAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
                error: (error, _) => Text('Ошибка загрузки ролей: $error'),
                data: (roles) {
                  if (roles.isEmpty) {
                    return const Text('Нет доступных ролей');
                  }
                  _selectedRoleId ??= roles.first.id;
                  return DropdownButtonFormField<int>(
                    value: _selectedRoleId,
                    decoration: const InputDecoration(labelText: 'Роль'),
                    items: roles
                        .map(
                          (role) => DropdownMenuItem(
                            value: role.id,
                            child: Text(role.name),
                          ),
                        )
                        .toList(),
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(() => _selectedRoleId = value),
                  );
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
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
              : const Text('Создать'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedRoleId == null) {
      setState(() => _error = 'Выберите роль');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final repository = ref.read(usersRepositoryProvider);
      final created = await repository.createUser(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        roleId: _selectedRoleId!,
      );
      if (!mounted) {
        return;
      }
      // Обновляем список пользователей
      ref.invalidate(allUsersFutureProvider);
      Navigator.of(context).pop(created);
    } on ApiException catch (error) {
      setState(() {
        _isSubmitting = false;
        _error = error.message;
      });
    } catch (error) {
      setState(() {
        _isSubmitting = false;
        _error = '$error';
      });
    }
  }

  String _generatePassword() {
    const groups = [
      'abcdefghijklmnopqrstuvwxyz',
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
      '0123456789',
      '!@#%&*+-=?',
    ];
    final alphabet = groups.join();
    final random = Random.secure();
    final codeUnits = groups
        .map((group) => group.codeUnitAt(random.nextInt(group.length)))
        .toList();
    codeUnits.addAll(List.generate(
      12,
      (_) => alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ));
    codeUnits.shuffle(random);
    return String.fromCharCodes(codeUnits);
  }
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.currentColor,
    required this.userName,
  });

  final String? currentColor;
  final String userName;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  Color _selectedColor = Colors.blue;
  String? _selectedColorHex;

  @override
  void initState() {
    super.initState();
    if (widget.currentColor != null && widget.currentColor!.isNotEmpty) {
      _selectedColor = _parseColor(widget.currentColor!);
      _selectedColorHex = widget.currentColor;
    } else {
      _selectedColorHex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Выбрать цвет для "${widget.userName}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ColorPicker(
              pickerColor: _selectedColor,
              onColorChanged: (Color color) {
                setState(() {
                  _selectedColor = color;
                  _selectedColorHex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
                });
              },
              labelTypes: const [],
              displayThumbColor: true,
              paletteType: PaletteType.hslWithSaturation,
              enableAlpha: false,
              pickerAreaHeightPercent: 0.7,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedColorHex = null;
                    });
                  },
                  child: const Text('Убрать цвет'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedColorHex ?? ''),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }
}
