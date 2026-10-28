import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';
import '../../data/models/user.dart';
import '../../data/repositories/assignments_repository.dart';
import '../../core/services/notification_service.dart';
import 'package:intl/intl.dart';

class AssignmentsController {
  AssignmentsController({
    required this.user,
    required this.assignmentsRepository,
  }) {
    _init();
  }

  final User user;
  final AssignmentsRepository assignmentsRepository;
  final NotificationService _notificationService = NotificationService();

  final _assignmentsSubject = BehaviorSubject<List<NewAssignment>>.seeded([]);
  final _lastCheckedSubject = BehaviorSubject<String?>.seeded(null);
  final _isCheckingSubject = BehaviorSubject<bool>.seeded(false);

  Stream<List<NewAssignment>> get assignmentsStream =>
      _assignmentsSubject.stream;
  Stream<bool> get isCheckingStream => _isCheckingSubject.stream;
  List<NewAssignment> get currentAssignments => _assignmentsSubject.value;

  Timer? _checkTimer;
  bool _isDisposed = false;

  void _init() {
    // Первая проверка сразу
    checkNewAssignments();

    // Затем проверка каждую минуту
    _checkTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => checkNewAssignments(),
    );
  }

  Future<void> checkNewAssignments() async {
    if (_isDisposed) return;

    try {
      _isCheckingSubject.add(true);

      final lastChecked = _lastCheckedSubject.value;
      final response = await assignmentsRepository.checkNewAssignments(
        lastChecked: lastChecked,
      );

      if (response.hasNew && response.assignments.isNotEmpty) {
        // Обновляем список назначений
        final current = _assignmentsSubject.value;
        final newOnes = response.assignments
            .where((newAssignment) => !current.any(
                  (existing) =>
                      existing.excursionId == newAssignment.excursionId &&
                      existing.assignedAt == newAssignment.assignedAt,
                ))
            .toList();

        if (newOnes.isNotEmpty) {
          _assignmentsSubject.add([...current, ...newOnes]);

          // Показываем уведомления для новых назначений
          for (final assignment in newOnes) {
            final roleText =
                assignment.roleInExcursion == 'driver' ? 'Водитель' : 'Гид';
            final dateTime = DateTime.parse(assignment.dateTime);
            final formattedDate =
                DateFormat('dd.MM.yyyy HH:mm').format(dateTime);

            await _notificationService.showAssignmentNotification(
              title: 'Новое назначение',
              body:
                  'Вас назначили $roleText на экскурсию "${assignment.title}"\n$formattedDate',
              excursionId: assignment.excursionId,
            );
          }
        }
      }

      // Обновляем время последней проверки
      _lastCheckedSubject.add(DateTime.now().toIso8601String());
    } catch (e) {
      // Ошибка при проверке - не критично, попробуем в следующий раз
      debugPrint('Error checking new assignments: $e');
    } finally {
      _isCheckingSubject.add(false);
    }
  }

  void markAsRead(int excursionId) {
    final current = _assignmentsSubject.value;
    _assignmentsSubject.add(
      current.where((a) => a.excursionId != excursionId).toList(),
    );
  }

  void clearAll() {
    _assignmentsSubject.add([]);
  }

  void dispose() {
    _isDisposed = true;
    _checkTimer?.cancel();
    _assignmentsSubject.close();
    _lastCheckedSubject.close();
    _isCheckingSubject.close();
  }
}
