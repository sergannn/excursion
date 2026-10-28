import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/internet_connection_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late int _checkInterval;
  final _intervalController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkInterval = SettingsService.instance.internetCheckInterval;
    _intervalController.text = _checkInterval.toString();
  }

  @override
  void dispose() {
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _saveInterval() async {
    final newInterval = int.tryParse(_intervalController.text);
    if (newInterval == null || newInterval < 5 || newInterval > 300) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Интервал должен быть от 5 до 300 секунд'),
            backgroundColor: Colors.red,
          ),
        );
      }
      _intervalController.text = _checkInterval.toString();
      return;
    }

    await SettingsService.instance.setInternetCheckInterval(newInterval);
    setState(() {
      _checkInterval = newInterval;
    });

    // Перезапускаем мониторинг с новым интервалом
    ref.read(internetConnectionServiceProvider).restartMonitoring();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Настройки сохранены'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Проверка интернета',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Интервал проверки подключения к интернету (в секундах)',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _intervalController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Интервал (секунды)',
                            border: OutlineInputBorder(),
                            helperText: 'От 5 до 300 секунд',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _saveInterval,
                        child: const Text('Сохранить'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Текущее значение: $_checkInterval секунд',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Рекомендуемые значения:\n'
                    '• 10-15 секунд - для активного использования\n'
                    '• 30-60 секунд - для экономии трафика',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
