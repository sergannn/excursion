import 'package:flutter/material.dart';

import '../../../data/models/booking.dart';
import '../../../data/models/stop.dart';

class EditBookingResult {
  const EditBookingResult({
    required this.customerName,
    required this.customerPhone,
    required this.debt,
    required this.stopId,
    required this.comment,
  });

  final String customerName;
  final String customerPhone;
  final double debt;
  final int stopId;
  final String comment;
}

class EditBookingDialog extends StatefulWidget {
  const EditBookingDialog({
    super.key,
    required this.booking,
    required this.stops,
  });

  final BookingItem booking;
  final List<Stop> stops;

  @override
  State<EditBookingDialog> createState() => _EditBookingDialogState();
}

class _EditBookingDialogState extends State<EditBookingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _debtController;
  late final TextEditingController _commentController;
  late int _stopId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.booking.customerName);
    _phoneController =
        TextEditingController(text: widget.booking.customerPhone);
    _debtController = TextEditingController(
      text: (widget.booking.debt ?? 0) == 0
          ? ''
          : (widget.booking.debt ?? 0).toStringAsFixed(0),
    );
    _commentController = TextEditingController(text: widget.booking.comment);
    final currentStopId = widget.booking.stop?.id;
    _stopId = widget.stops.any((stop) => stop.id == currentStopId)
        ? currentStopId!
        : widget.stops.first.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _debtController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Место ${widget.booking.seat.seatNumber}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Имя пассажира'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите имя пассажира'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration:
                      const InputDecoration(labelText: 'Телефон пассажира'),
                  keyboardType: TextInputType.phone,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Введите телефон пассажира'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _stopId,
                  decoration: const InputDecoration(labelText: 'Остановка'),
                  items: widget.stops
                      .map(
                        (stop) => DropdownMenuItem(
                          value: stop.id,
                          child: Text(stop.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _stopId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _debtController,
                  decoration: InputDecoration(
                    labelText: 'Долг',
                    suffixText: '₽',
                    helperText:
                        'Цена билета: ${widget.booking.price.toStringAsFixed(0)} ₽',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (value) {
                    final normalized = value?.trim().replaceAll(',', '.') ?? '';
                    if (normalized.isEmpty) return null;
                    final debt = double.tryParse(normalized);
                    if (debt == null || debt < 0)
                      return 'Введите корректный долг';
                    if (debt > widget.booking.price) {
                      return 'Долг не должен быть больше цены билета';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _commentController,
                  decoration: const InputDecoration(
                    labelText: 'Комментарий к месту',
                    hintText: 'Посадить ближе, длинные ноги, коляска...',
                  ),
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 1000,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final normalized = _debtController.text.trim().replaceAll(',', '.');
            Navigator.of(context).pop(
              EditBookingResult(
                customerName: _nameController.text.trim(),
                customerPhone: _phoneController.text.trim(),
                debt: normalized.isEmpty ? 0 : double.parse(normalized),
                stopId: _stopId,
                comment: _commentController.text.trim(),
              ),
            );
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
