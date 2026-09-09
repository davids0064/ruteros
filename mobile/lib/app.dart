import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_screen.dart';
import 'features/gyms/gym_home_screen.dart';
import 'state/session_controller.dart';
import 'ui/theme.dart';

class BoulderCoSetterApp extends StatelessWidget {
  const BoulderCoSetterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boulder Co-Setter',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: const _SessionGate(),
    );
  }
}

/// Decide la pantalla raíz según haya sesión o no.
///
/// El perfil se rehidrata siempre desde `GET /auth/me` (RNF-1): en disco sólo
/// viven los tokens.
class _SessionGate extends ConsumerWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return switch (session) {
      AsyncData(:final value) =>
        value == null ? const AuthScreen() : const GymHomeScreen(),
      AsyncError() => const AuthScreen(),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}
