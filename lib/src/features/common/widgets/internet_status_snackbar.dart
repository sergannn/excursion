import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/internet_connection_service.dart';

/// Виджет для отображения snackbar при потере интернета
class InternetStatusSnackbar extends ConsumerStatefulWidget {
  final Widget child;

  const InternetStatusSnackbar({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<InternetStatusSnackbar> createState() =>
      _InternetStatusSnackbarState();
}

class _InternetStatusSnackbarState
    extends ConsumerState<InternetStatusSnackbar> {
  bool _wasOffline = false;

  @override
  Widget build(BuildContext context) {
    final internetStatusAsync = ref.watch(internetStatusProvider);

    internetStatusAsync.whenData((hasInternet) {
      if (!hasInternet && !_wasOffline) {
        // Интернет только что пропал
        _wasOffline = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Нет подключения к интернету'),
                  ],
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      } else if (hasInternet && _wasOffline) {
        // Интернет восстановлен
        _wasOffline = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.wifi, color: Colors.white),
                    SizedBox(width: 12),
                    Text('Подключение к интернету восстановлено'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        });
      }
    });

    return widget.child;
  }
}
