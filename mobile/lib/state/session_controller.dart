import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth.dart';
import 'providers.dart';

/// Sesión del usuario.
///
/// RNF-1: en disco sólo viven los tokens (`TokenStore`). El perfil se rehidrata
/// desde `GET /auth/me` en cada arranque, nunca desde una caché local.
class SessionController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final tokens = ref.watch(tokenStoreProvider);
    await tokens.load();
    if (tokens.accessToken == null) return null;

    try {
      return await ref.read(authRepositoryProvider).me();
    } catch (_) {
      // Token caducado o revocado: se arranca sin sesión, sin ruido.
      await tokens.clear();
      return null;
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final session = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
          );
      await _persist(session);
      return session.user;
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final session = await ref.read(authRepositoryProvider).register(
            email: email,
            password: password,
            username: username,
            displayName: displayName,
          );
      await _persist(session);
      return session.user;
    });
  }

  /// Relee el perfil. Necesario tras crear un boulder o ser autorizado: el
  /// access token vigente todavía no lleva esa membresía en sus claims.
  Future<void> reload() async {
    if (state.value == null) return;
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).me());
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncValue.data(null);
  }

  /// Invocado por el interceptor cuando el refresh token deja de valer.
  void forceLogout() {
    ref.read(tokenStoreProvider).clear();
    state = const AsyncValue.data(null);
  }

  Future<void> _persist(AuthSession session) => ref
      .read(tokenStoreProvider)
      .save(
        accessToken: session.accessToken,
        refreshToken: session.refreshToken,
      );
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, UserProfile?>(SessionController.new);

/// Perfil ya autenticado. Sólo se lee desde pantallas que exigen sesión.
final currentUserProvider = Provider<UserProfile?>(
  (ref) => ref.watch(sessionProvider).value,
);
