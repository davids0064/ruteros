import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Lectura del ángulo de inclinación del muro (RF-3.1, US-03).
///
/// **Cómo se mide:** el teléfono se apoya de plano contra el muro, con la
/// pantalla mirando hacia fuera. El acelerómetro entrega el vector gravedad en
/// coordenadas del dispositivo; el ángulo entre ese vector y el plano de la
/// pantalla es exactamente la desviación del muro respecto de la vertical.
///
/// Convención de signo, la misma del motor de dificultad (04 §6):
/// **desplome = positivo**, placa tumbada = negativo, pared vertical = 0.
class Inclinometer {
  Inclinometer({Stream<AccelerometerEvent>? source})
      : _source = source ??
            accelerometerEventStream(
                samplingPeriod: SensorInterval.uiInterval);

  final Stream<AccelerometerEvent> _source;

  /// Media móvil exponencial: el acelerómetro es ruidoso y el setter necesita
  /// un número que se quede quieto para poder leerlo.
  static const _smoothing = 0.15;

  Stream<double> get angleStream {
    double? smoothed;
    return _source.map((event) {
      final raw = inclineFromGravity(event.x, event.y, event.z);
      smoothed = smoothed == null
          ? raw
          : smoothed! + _smoothing * (raw - smoothed!);
      return double.parse(smoothed!.toStringAsFixed(1));
    });
  }

  /// Ángulo en grados, acotado a [-90, 90] como exige `chk_wall_incline`.
  static double inclineFromGravity(double x, double y, double z) {
    final inPlane = math.sqrt(x * x + y * y);
    if (inPlane == 0 && z == 0) return 0;
    final degrees = math.atan2(z, inPlane) * 180 / math.pi;
    return degrees.clamp(-90.0, 90.0);
  }
}
