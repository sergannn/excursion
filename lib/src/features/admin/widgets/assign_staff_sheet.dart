import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/excursion.dart';
import '../../../data/models/user_summary.dart';
import '../../../data/providers.dart';

class AssignStaffSheet extends ConsumerStatefulWidget {
  const AssignStaffSheet({
    super.key,
    required this.excursion,
    this.excursionDate,
    this.time,
  });

  final Excursion excursion;
  final String? excursionDate; // YYYY-MM-DD
  final String? time; // HH:MM

  @override
  ConsumerState<AssignStaffSheet> createState() => _AssignStaffSheetState();
}

class _AssignStaffSheetState extends ConsumerState<AssignStaffSheet> {
  final Set<int> _selectedDrivers = {};
  final Set<int> _selectedGuides = {};
  late final TextEditingController _slotLimitController;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _slotLimitController = TextEditingController(
      text: widget.excursion.maxSeats.toString(),
    );
    // Фильтруем назначенный персонал по дате/времени
    final targetDate = widget.excursionDate ??
        DateFormat('yyyy-MM-dd').format(widget.excursion.dateTime);
    final targetTime =
        widget.time ?? DateFormat('HH:mm').format(widget.excursion.dateTime);

    for (final staff in widget.excursion.assignedStaff) {
      // Показываем только назначения на эту дату/время или без даты (на все)
      final staffDate = staff.excursionDate;
      final staffTime = staff.time;
      final matchesDate = staffDate == null || staffDate == targetDate;
      final matchesTime = staffTime == null || staffTime == targetTime;

      if (matchesDate && matchesTime) {
        if (staff.roleInExcursion == 'driver') {
          _selectedDrivers.add(staff.id);
        } else if (staff.roleInExcursion == 'guide') {
          _selectedGuides.add(staff.id);
        }
      }
    }
  }

  @override
  void dispose() {
    _slotLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersFutureProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) {
        return SafeArea(
          top: true,
          child: Material(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Персонал и лимит рейса',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.excursion.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: usersAsync.when(
                        loading: () => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        error: (error, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child:
                                Text('Ошибка загрузки пользователей: $error'),
                          ),
                        ),
                        data: (users) {
                          final drivers = users
                              .where((user) => user.roleName
                                  .toLowerCase()
                                  .contains('водител'))
                              .toList();
                          final guides = users
                              .where((user) => user.roleName
                                  .toLowerCase()
                                  .contains('экскурсов'))
                              .toList();
                          final autoGuideDrivers = _selectedGuides.isEmpty
                              ? drivers
                                  .where((user) =>
                                      _selectedDrivers.contains(user.id))
                                  .toList()
                              : const <UserSummary>[];

                          return ListView(
                            controller: controller,
                            padding: const EdgeInsets.all(16),
                            children: [
                              TextFormField(
                                controller: _slotLimitController,
                                decoration: InputDecoration(
                                  labelText: 'Лимит мест этого рейса',
                                  helperText:
                                      'От 1 до ${widget.excursion.baseMaxSeats}. Не зависит от назначения автобусов.',
                                  prefixIcon: const Icon(Icons.event_seat),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 24),
                              _StaffSection(
                                title: 'Водители',
                                users: drivers,
                                selected: _selectedDrivers,
                                onChanged: (update) => setState(() {
                                  update(_selectedDrivers);
                                }),
                              ),
                              const SizedBox(height: 24),
                              _StaffSection(
                                title: 'Экскурсоводы',
                                users: guides,
                                selected: _selectedGuides,
                                autoGuideDrivers: autoGuideDrivers,
                                onChanged: (update) => setState(() {
                                  update(_selectedGuides);
                                }),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Отмена'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Сохранить'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_isSubmitting)
                  Positioned.fill(
                    child: AbsorbPointer(
                      child: ColoredBox(
                        color: Colors.black26,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 3),
                                ),
                                SizedBox(height: 12),
                                Text('Сохраняем назначения...'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(assignmentsRepositoryProvider);
      final targetDate = widget.excursionDate ??
          DateFormat('yyyy-MM-dd').format(widget.excursion.dateTime);
      final targetTime =
          widget.time ?? DateFormat('HH:mm').format(widget.excursion.dateTime);
      final slotMaxSeats = int.tryParse(_slotLimitController.text.trim());
      if (slotMaxSeats == null ||
          slotMaxSeats < 1 ||
          slotMaxSeats > widget.excursion.baseMaxSeats) {
        throw FormatException(
          'Лимит должен быть от 1 до ${widget.excursion.baseMaxSeats}',
        );
      }

      await repository.assignStaff(
        excursionId: widget.excursion.id,
        assignments: [
          ..._selectedDrivers.map(
            (id) => {'user_id': id, 'role_in_excursion': 'driver'},
          ),
          ..._selectedGuides.map(
            (id) => {'user_id': id, 'role_in_excursion': 'guide'},
          ),
        ],
        excursionDate: targetDate,
        time: targetTime,
        slotMaxSeats: slotMaxSeats,
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Назначения обновлены'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ошибка: $error'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _StaffSection extends StatelessWidget {
  const _StaffSection({
    required this.title,
    required this.users,
    required this.selected,
    required this.onChanged,
    this.autoGuideDrivers = const [],
  });

  final String title;
  final List<UserSummary> users;
  final Set<int> selected;
  final void Function(void Function(Set<int>)) onChanged;
  final List<UserSummary> autoGuideDrivers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (title == 'Экскурсоводы' && autoGuideDrivers.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.indigo.withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: Colors.indigo),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Отдельный экскурсовод не назначен. Водитель автоматически считается экскурсоводом.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.indigo.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: autoGuideDrivers
                      .map(
                        (user) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.indigo),
                            color: Colors.white,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.directions_bus,
                                size: 16,
                                color: Colors.indigo,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                user.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'авто',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Colors.indigo.shade400,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
        if (users.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Сотрудников с такой ролью пока нет'),
          )
        else
          Wrap(
            spacing: 8,
            children: users
                .map(
                  (user) => FilterChip(
                    avatar: title == 'Водители' && user.busId == null
                        ? const Icon(Icons.warning_amber_rounded, size: 18)
                        : null,
                    label: Text(
                      title == 'Водители'
                          ? user.busId == null
                              ? '${user.name} · без автобуса'
                              : '${user.name} · автобус ${user.busNumber ?? user.busId}'
                          : user.name,
                    ),
                    selected: selected.contains(user.id),
                    onSelected: (value) => onChanged((set) {
                      if (value) {
                        set.add(user.id);
                      } else {
                        set.remove(user.id);
                      }
                    }),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
