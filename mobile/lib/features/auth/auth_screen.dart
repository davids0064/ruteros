import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session_controller.dart';
import '../../ui/widgets/common.dart';

/// Registro e inicio de sesión — RF-4.1, US-04.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();

  bool _registering = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(sessionProvider.notifier);
    if (_registering) {
      await controller.register(
        email: _email.text.trim(),
        password: _password.text,
        username: _username.text.trim(),
        displayName: _displayName.text.trim().isEmpty
            ? null
            : _displayName.text.trim(),
      );
    } else {
      await controller.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    }

    if (!mounted) return;
    final state = ref.read(sessionProvider);
    if (state.hasError) showError(context, state.error!);
  }

  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(sessionProvider).isLoading;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.terrain_rounded,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text('Boulder Co-Setter',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      'Diseña, firma y comparte tus bloques.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Introduce un correo válido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Obligatoria';
                        // 04 §2.3: mínimo 10 caracteres.
                        if (_registering && v.length < 10) {
                          return 'Mínimo 10 caracteres';
                        }
                        return null;
                      },
                    ),
                    if (_registering) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'Usuario',
                          helperText: 'minúsculas, dígitos y _ (3-60)',
                        ),
                        validator: (v) =>
                            RegExp(r'^[a-z0-9_]{3,60}$').hasMatch(v ?? '')
                                ? null
                                : 'Sólo minúsculas, dígitos y guion bajo',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _displayName,
                        decoration: const InputDecoration(
                            labelText: 'Nombre visible (opcional)'),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2.5),
                            )
                          : Text(_registering ? 'Crear cuenta' : 'Entrar'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => _registering = !_registering),
                      child: Text(_registering
                          ? 'Ya tengo cuenta'
                          : 'Crear una cuenta nueva'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
