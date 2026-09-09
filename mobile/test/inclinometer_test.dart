import 'package:boulder_cosetter/core/sensors/inclinometer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lectura de inclinación — RF-3.1.
///
/// Convención de 04 §6: desplome positivo, placa tumbada negativa.
void main() {
  group('Inclinometer.inclineFromGravity', () {
    const g = 9.81;

    test('teléfono de plano contra un muro vertical -> 0°', () {
      // Gravedad íntegra en el plano de la pantalla, nada en el eje Z.
      expect(Inclinometer.inclineFromGravity(0, -g, 0), closeTo(0, 0.01));
    });

    test('muro desplomado -> ángulo positivo', () {
      // 45°: la gravedad se reparte por igual entre el plano y el eje Z.
      final angle = Inclinometer.inclineFromGravity(0, -6.94, 6.94);
      expect(angle, closeTo(45, 0.5));
      expect(angle, greaterThan(0));
    });

    test('placa tumbada -> ángulo negativo', () {
      final angle = Inclinometer.inclineFromGravity(0, -6.94, -6.94);
      expect(angle, closeTo(-45, 0.5));
    });

    test('techo puro -> 90°', () {
      expect(Inclinometer.inclineFromGravity(0, 0, g), closeTo(90, 0.01));
    });

    test('nunca se sale de [-90, 90], que es lo que acepta chk_wall_incline',
        () {
      for (final sample in [
        [0.0, 0.0, 100.0],
        [0.0, 0.0, -100.0],
        [50.0, -50.0, 50.0],
      ]) {
        final angle =
            Inclinometer.inclineFromGravity(sample[0], sample[1], sample[2]);
        expect(angle, inInclusiveRange(-90, 90));
      }
    });

    test('con el sensor en cero devuelve 0 en lugar de NaN', () {
      expect(Inclinometer.inclineFromGravity(0, 0, 0), 0);
    });

    test('la rotación del teléfono sobre su propio eje no altera la lectura',
        () {
      // Girar el móvil en el plano del muro reparte la gravedad entre X e Y
      // sin cambiar el ángulo del muro.
      final vertical = Inclinometer.inclineFromGravity(0, -g, 0);
      final girado = Inclinometer.inclineFromGravity(-6.94, -6.94, 0);
      expect(girado, closeTo(vertical, 0.01));
    });
  });
}
