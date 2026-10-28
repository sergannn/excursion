import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/internet_connection_service.dart';

/// Виджет индикатора статуса интернета
/// Отображает маленький кружок в верхней части экрана
class InternetStatusIndicator extends ConsumerWidget {
  const InternetStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Убеждаемся, что провайдер инициализирован
    ref.watch(internetConnectionServiceProvider);
    final internetStatusAsync = ref.watch(internetStatusProvider);

    return internetStatusAsync.when(
      data: (hasInternet) => Positioned(
        top: MediaQuery.of(context).padding.top + 4,
        right: 12,
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            type: MaterialType.transparency,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: hasInternet ? Colors.green : Colors.red,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (hasInternet ? Colors.green : Colors.red).withOpacity(0.7),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      loading: () => Positioned(
        top: MediaQuery.of(context).padding.top + 4,
        right: 12,
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            type: MaterialType.transparency,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
      error: (_, __) => Positioned(
        top: MediaQuery.of(context).padding.top + 4,
        right: 12,
        child: IgnorePointer(
          child: Material(
            elevation: 4,
            type: MaterialType.transparency,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
