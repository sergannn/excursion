import 'package:flutter/material.dart';

class CancellationReasonDialog extends StatefulWidget {
  const CancellationReasonDialog({super.key});

  @override
  State<CancellationReasonDialog> createState() => _CancellationReasonDialogState();
}

class _CancellationReasonDialogState extends State<CancellationReasonDialog> {
  static const _reasons = <String>[
    'Клиент заболел',
    'Клиент передумал',
    'Клиент не явился',
    'Другое',
  ];

  String _selectedReason = _reasons.first;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Причина отмены'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedReason,
            items: _reasons
                .map(
                  (reason) => DropdownMenuItem(
                    value: reason,
                    child: Text(reason),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              if (value != null) {
                _selectedReason = value;
              }
            }),
            decoration: const InputDecoration(
              labelText: 'Выберите причину',
            ),
          ),
          if (_selectedReason == 'Другое') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _otherController,
              decoration: const InputDecoration(
                labelText: 'Укажите причину',
              ),
              maxLines: 3,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final reason = _selectedReason == 'Другое'
                ? _otherController.text.trim()
                : _selectedReason;
            if (reason.isEmpty) {
              return;
            }
            Navigator.of(context).pop(reason);
          },
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}
