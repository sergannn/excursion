import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/login_screen.dart';
import '../seller/seller_home.dart';
import '../admin/admin_home.dart';
import '../staff/staff_home.dart';
import 'widgets/internet_status_snackbar.dart';
import '../../core/services/internet_connection_service.dart';
import '../../core/api/api_client.dart';

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Инициализируем сервис проверки интернета
    final internetService = ref.watch(internetConnectionServiceProvider);
    
    // Настраиваем API клиент с сервисом проверки интернета
    // Это нужно сделать один раз при первом рендере
    ApiClient.instance.setInternetService(internetService);
    
    final authState = ref.watch(authControllerProvider);
    
    final content = InternetStatusSnackbar(
      child: authState.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (error, stackTrace) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text('Ошибка: $error'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                    child: const Text('Вернуться к входу'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (user) {
          if (user == null) {
            return const LoginScreen();
          }
          final normalizedRole = user.role.trim().toLowerCase();
          final isAdmin = normalizedRole.contains('admin') || user.roleId == 1;
          final isDriver = user.roleId == 3;
          final isGuide = normalizedRole.contains('гид') || 
                          normalizedRole.contains('guide') ||
                          normalizedRole.contains('экскурсовод');
          
          if (isAdmin) {
            return AdminHomePage(user: user);
          }
          if (isDriver || isGuide) {
            return StaffHomePage(user: user);
          }
          return SellerHomePage(user: user);
        },
      ),
    );
    
    return content;
  }
}

