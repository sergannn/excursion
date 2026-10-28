import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/models/excursion.dart';
import '../../../data/repositories/seat_permission_repository.dart';
import '../../../core/api/api_client.dart';
import '../../../data/providers.dart';

class SeatAccessRequestDialog extends ConsumerStatefulWidget {
  const SeatAccessRequestDialog({
    super.key,
    required this.excursion,
    required this.excursionDate,
    required this.seatNumber,
  });

  final Excursion excursion;
  final DateTime excursionDate;
  final int seatNumber;

  @override
  ConsumerState<SeatAccessRequestDialog> createState() => _SeatAccessRequestDialogState();
}

class _SeatAccessRequestDialogState extends ConsumerState<SeatAccessRequestDialog> {
  final _reasonController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (_loading) return;

    setState(() => _loading = true);

    try {
      final client = ref.read(apiClientProvider);
      final repo = SeatPermissionRepository(client);
      
      await repo.createRequest(
        excursionId: widget.excursion.id,
        excursionDate: DateFormat('yyyy-MM-dd').format(widget.excursionDate),
        seatNumber: widget.seatNumber,
        reason: _reasonController.text.trim().isEmpty 
            ? null 
            : _reasonController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запрос отправлен администратору'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Запросить доступ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Для бронирования места ${widget.seatNumber} необходимо разрешение администратора.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Экскурсия: ${widget.excursion.title}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Дата: ${DateFormat('dd.MM.yyyy').format(widget.excursionDate)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(
              labelText: 'Причина запроса (необязательно)',
              hintText: 'Укажите причину, по которой вам нужен доступ...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            enabled: !_loading,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _submitRequest,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Отправить запрос'),
        ),
      ],
    );
  }
}


