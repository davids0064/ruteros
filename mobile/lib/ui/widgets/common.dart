import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';

/// Traduce un error a un mensaje accionable.
///
/// Los `errorCode` de 04 §2.2 son constantes estables del contrato: la UI
/// decide en función de ellos, nunca del texto.
String describeError(Object error) {
  if (error is! ApiException) return 'Ha ocurrido un error inesperado.';

  return switch (error.errorCode) {
    'HOLD_NOT_AVAILABLE' =>
      'Alguna presa del bloque ya está montada en otra ruta. Actualiza el inventario.',
    'DUPLICATE_HOLD_IN_ROUTE' => 'Has colocado la misma presa dos veces.',
    'ROUTE_ALREADY_DISMANTLED' => 'Este bloque ya estaba desmontado.',
    'NOT_GYM_MEMBER' => 'No eres miembro autorizado de este boulder.',
    'NOT_GYM_ADMIN' => 'Necesitas permisos de administrador del boulder.',
    'NOT_ROUTE_AUTHOR' => 'Sólo el setter que firmó el bloque puede modificarlo.',
    'GRADE_SYSTEM_MISMATCH' =>
      'Ese grado no pertenece al sistema configurado para el muro.',
    'EMAIL_ALREADY_REGISTERED' => 'Ese correo ya tiene una cuenta.',
    'VALIDATION_FAILED' => error.fieldMessages.isEmpty
        ? error.message
        : error.fieldMessages.join('\n'),
    _ => error.message,
  };
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(describeError(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
    ));
}

void showInfo(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Estado vacío con una acción sugerida.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Muestra el color de un set de presas.
class ColorDot extends StatelessWidget {
  const ColorDot({super.key, required this.colorHex, this.size = 16});

  final String colorHex;
  final double size;

  static Color parse(String colorHex) {
    final hex = colorHex.replaceFirst('#', '');
    final value = int.tryParse(hex, radix: 16);
    return value == null ? const Color(0xFF888888) : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: parse(colorHex),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26),
        ),
      );
}
