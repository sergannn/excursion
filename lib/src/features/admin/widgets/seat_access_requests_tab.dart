import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/seat_access_request.dart';
import '../../../data/repositories/seat_permission_repository.dart';
import '../../../core/api/api_client.dart';
import '../../../data/providers.dart';

class SeatAccessRequestsTab extends ConsumerStatefulWidget {
  const SeatAccessRequestsTab({super.key});

  @override
  ConsumerState<SeatAccessRequestsTab> createState() => _SeatAccessRequestsTabState();
}

class _SeatAccessRequestsTabState extends ConsumerState<SeatAccessRequestsTab> {
  List<SeatAccessRequest> _requests = [];
  bool _loading = false;
  String _filterStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      final requests = await repo.fetchRequests(status: _filterStatus);
      setState(() {
        _requests = requests;
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

  Future<void> _approveRequest(int requestId) async {
    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      await repo.approveRequest(requestId);
      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запрос одобрен'),
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

  Future<void> _rejectRequest(int requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Отклонить запрос?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отклонить'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      await repo.rejectRequest(requestId);
      _loadRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запрос отклонен'),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Ожидает';
      case 'approved':
        return 'Одобрен';
      case 'rejected':
        return 'Отклонен';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Запросы доступа к местам 1-2'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRequests,
            tooltip: 'Обновить',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('Ожидают'),
                  selected: _filterStatus == 'pending',
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _filterStatus = 'pending';
                        _loadRequests();
                      });
                    }
                  },
                ),
              ),
              Expanded(
                child: ChoiceChip(
                  label: const Text('Все'),
                  selected: _filterStatus.isEmpty,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _filterStatus = '';
                        _loadRequests();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(child: Text('Нет запросов'))
              : ListView.builder(
                  itemCount: _requests.length,
                  itemBuilder: (context, index) {
                    final request = _requests[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ListTile(
                        title: Text(
                          '${request.excursion?.title ?? 'Экскурсия ${request.excursionId}'} - Место ${request.seatNumber}',
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${request.user?.name ?? 'Пользователь ${request.userId}'}'),
                            Text(DateFormat('dd.MM.yyyy').format(request.excursionDate)),
                            if (request.reason != null) Text('Причина: ${request.reason}'),
                            Chip(
                              label: Text(_getStatusText(request.status)),
                              backgroundColor: _getStatusColor(request.status).withOpacity(0.2),
                            ),
                          ],
                        ),
                        trailing: request.isPending
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check, color: Colors.green),
                                    onPressed: () => _approveRequest(request.id),
                                    tooltip: 'Одобрить',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, color: Colors.red),
                                    onPressed: () => _rejectRequest(request.id),
                                    tooltip: 'Отклонить',
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}


