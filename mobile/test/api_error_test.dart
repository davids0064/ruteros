import 'package:boulder_cosetter/core/api/api_exception.dart';
import 'package:boulder_cosetter/ui/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modelo de error único — 04_COMPONENT_SPECS.md §2.2.
void main() {
  group('ApiException.fromResponse', () {
    test('mapea la forma canónica del backend', () {
      final error = ApiException.fromResponse(409, {
        'statusCode': 409,
        'errorCode': 'HOLD_NOT_AVAILABLE',
        'message': 'Alguna presa del bloque ya no está disponible.',
        'timestamp': '2026-09-03T10:00:00.000Z',
        'path': '/api/v1/routes',
      });

      expect(error.errorCode, 'HOLD_NOT_AVAILABLE');
      expect(error.statusCode, 409);
      expect(error.isHoldConflict, isTrue);
      expect(error.isUnauthenticated, isFalse);
    });

    test('un cuerpo que no sigue el contrato cae a INTERNAL_ERROR', () {
      final error = ApiException.fromResponse(500, '<html>502 Bad Gateway</html>');
      expect(error.errorCode, 'INTERNAL_ERROR');
      expect(error.statusCode, 500);
    });

    test('sin respuesta se reporta como falta de conexión', () {
      final error = ApiException.fromResponse(null, null);
      expect(error.errorCode, 'INTERNAL_ERROR');
      expect(error.message, contains('conexión'));
    });

    test('extrae los errores de validación campo a campo', () {
      final error = ApiException.fromResponse(400, {
        'statusCode': 400,
        'errorCode': 'VALIDATION_FAILED',
        'message': 'La petición no supera la validación.',
        'details': [
          {
            'field': 'password',
            'constraints': {
              'minLength': 'La contraseña debe tener al menos 10 caracteres.'
            }
          },
          {
            'field': 'colorHex',
            'constraints': {'matches': 'colorHex debe tener la forma #RRGGBB.'}
          },
        ],
      });

      expect(error.fieldMessages, hasLength(2));
      expect(error.fieldMessages.first, contains('10 caracteres'));
    });

    test('sin `details` la lista de mensajes es vacía, no nula', () {
      final error = ApiException.fromResponse(400, {
        'statusCode': 400,
        'errorCode': 'VALIDATION_FAILED',
        'message': 'Inválido',
      });
      expect(error.fieldMessages, isEmpty);
    });
  });

  group('describeError', () {
    test('traduce cada errorCode del contrato a lenguaje del setter', () {
      const codes = [
        'HOLD_NOT_AVAILABLE',
        'DUPLICATE_HOLD_IN_ROUTE',
        'ROUTE_ALREADY_DISMANTLED',
        'NOT_GYM_MEMBER',
        'NOT_GYM_ADMIN',
        'NOT_ROUTE_AUTHOR',
        'GRADE_SYSTEM_MISMATCH',
        'EMAIL_ALREADY_REGISTERED',
      ];

      for (final code in codes) {
        final message = describeError(ApiException(
          statusCode: 409,
          errorCode: code,
          message: 'mensaje del servidor',
        ));
        // No se filtra el mensaje crudo del backend: la UI habla su idioma.
        expect(message, isNot('mensaje del servidor'), reason: code);
        expect(message, isNotEmpty, reason: code);
      }
    });

    test('un código desconocido cae al mensaje del servidor', () {
      final message = describeError(const ApiException(
        statusCode: 418,
        errorCode: 'UNKNOWN_CODE',
        message: 'Soy una tetera',
      ));
      expect(message, 'Soy una tetera');
    });

    test('un error que no es de la API no filtra detalles internos', () {
      expect(describeError(StateError('boom')), 'Ha ocurrido un error inesperado.');
    });
  });
}
