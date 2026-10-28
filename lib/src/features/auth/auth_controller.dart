import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/models/user.dart';
import '../../core/api/api_exception.dart';

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<User?>>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  return AuthController(repository);
});

class AuthController extends StateNotifier<AsyncValue<User?>> {
  AuthController(this._repository) : super(const AsyncValue.loading()) {
    _restore();
  }

  final AuthRepository _repository;

  Future<void> _restore() async {
    try {
      final user = await _repository.loadPersistedUser();
      state = AsyncValue.data(user);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<String?> signIn(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final user = await _repository.signIn(email, password);
      if (user == null) {
        state = const AsyncValue.data(null);
        return 'Не удалось войти. Проверьте данные.';
      }
      state = AsyncValue.data(user);
      return null; // Успешный вход, ошибки нет
    } on ApiException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return e.message; // Возвращаем сообщение об ошибке
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return 'Произошла ошибка при входе.';
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    try {
      final updated = await _repository.fetchCurrentUser();
      state = AsyncValue.data(updated ?? current);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
