import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'heuristic_category.dart';
import 'segment_service.dart';

/// Motor de segmentación por color, en el dispositivo (RF-2.1).
///
/// Implementa el pipeline de 04 §1.2 apoyándose en el filtro por `colorHex` que
/// el propio §1.1 declara como entrada, y que US-02 pone en el centro del flujo
/// ("tomar fotos de mis sets de presas **por color**"):
///
///   1. redimensiona a 640 px de lado mayor conservando la relación de aspecto;
///   2. construye la máscara de los píxeles cercanos al color del set;
///   3. etiqueta componentes conexas y descarta las manchas irrelevantes;
///   4. recorta cada componente aplicando la máscara como canal alpha;
///   5. sugiere categoría con la heurística de §1.4.
///
/// Todo el trabajo pesado corre en un isolate: el hilo de UI no pierde un
/// fotograma mientras se procesa el set (RNF-2).
///
/// Sustituir esto por YOLOv8-seg sobre ONNX Runtime no cambia el contrato:
/// basta con otra implementación de [SegmentService].
class ColorSegmentEngine implements SegmentService {
  const ColorSegmentEngine({
    this.tolerance = 0.25,
    this.minAreaRatio = 0.0008,
    this.maxSide = 640,
  });

  /// Distancia máxima al color del set, normalizada a [0, 1].
  ///
  /// Calibrado sobre [colorDistance]: un blanco o un gris de fondo quedan por
  /// encima de 0.43 y una presa del color del set en penumbra por debajo de
  /// 0.23. Colores vecinos en el círculo cromático (naranja contra amarillo)
  /// sí pueden solaparse — por eso la revisión humana previa al alta no es
  /// opcional (§1.4: "siempre editable por el usuario").
  final double tolerance;

  /// Área mínima de una componente, como fracción de la imagen redimensionada.
  /// Filtra ruido y reflejos sin descartar presas de pie.
  final double minAreaRatio;

  /// 04 §1.2 paso 1: lado mayor de la imagen de trabajo.
  final int maxSide;

  @override
  Future<List<SegmentedHold>> processSetImage({
    required Uint8List imageBytes,
    required String colorHex,
    double scaleCmPerPx = 0.25,
  }) =>
      Isolate.run(() => _run(
            imageBytes: imageBytes,
            colorHex: colorHex,
            scaleCmPerPx: scaleCmPerPx,
            tolerance: tolerance,
            minAreaRatio: minAreaRatio,
            maxSide: maxSide,
          ));
}

/// Convierte `#RRGGBB` a componentes 0-255. Acepta con o sin almohadilla.
({int r, int g, int b}) parseHexColor(String colorHex) {
  final hex = colorHex.replaceFirst('#', '').trim();
  if (hex.length != 6) {
    throw FormatException('colorHex debe tener la forma #RRGGBB', colorHex);
  }
  final value = int.parse(hex, radix: 16);
  return (
    r: (value >> 16) & 0xFF,
    g: (value >> 8) & 0xFF,
    b: value & 0xFF,
  );
}

/// Distancia perceptual normalizada entre dos colores RGB, en [0, 1].
///
/// Usa la aproximación ponderada de Thiadmer Riemersma: es mucho más fiel al
/// ojo que la distancia euclídea plana y no exige convertir a Lab, que sería
/// caro para cientos de miles de píxeles.
///
/// La raíz al final es lo que la convierte en una distancia y no en un
/// cuadrado: sin ella todo el rango útil se apelmaza cerca de cero y cualquier
/// umbral razonable acaba tragándose el fondo de la foto.
double colorDistance(int r1, int g1, int b1, int r2, int g2, int b2) {
  final rMean = (r1 + r2) / 2;
  final dr = (r1 - r2).toDouble();
  final dg = (g1 - g2).toDouble();
  final db = (b1 - b2).toDouble();
  final sum = (2 + rMean / 256) * dr * dr +
      4 * dg * dg +
      (2 + (255 - rMean) / 256) * db * db;
  // Máximo del ponderado con dr = dg = db = 255: ~649_730.
  const maxSum = 649730.0;
  return math.sqrt((sum / maxSum).clamp(0.0, 1.0)).toDouble();
}

List<SegmentedHold> _run({
  required Uint8List imageBytes,
  required String colorHex,
  required double scaleCmPerPx,
  required double tolerance,
  required double minAreaRatio,
  required int maxSide,
}) {
  // Una foto corrupta o un formato no reconocido no puede tumbar la
  // catalogación: los decodificadores de `image` lanzan además de devolver
  // null, así que se cubren las dos vías.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(imageBytes);
  } catch (_) {
    return const [];
  }
  if (decoded == null) return const [];

  // Paso 1 — redimensionar conservando la relación de aspecto.
  final scale = maxSide / (decoded.width > decoded.height ? decoded.width : decoded.height);
  final work = scale < 1
      ? img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.average,
        )
      : decoded;

  // El bounding box se reporta en píxeles de la imagen ORIGINAL: es lo que
  // hace comparable `scale_cm_per_px` entre fotos tomadas a distinta
  // resolución.
  final backScale = decoded.width / work.width;

  final target = parseHexColor(colorHex);
  final w = work.width;
  final h = work.height;

  // Paso 2 — máscara por cercanía de color.
  final mask = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = work.getPixel(x, y);
      final d = colorDistance(
          p.r.toInt(), p.g.toInt(), p.b.toInt(), target.r, target.g, target.b);
      if (d <= tolerance) mask[y * w + x] = 1;
    }
  }

  // Paso 3 — componentes conexas (8-vecindad) sobre la máscara.
  final minArea = (w * h * minAreaRatio).round().clamp(24, 1 << 30);
  final labels = Int32List(w * h);
  final stack = <int>[];
  final results = <SegmentedHold>[];
  var nextLabel = 0;

  for (var start = 0; start < mask.length; start++) {
    if (mask[start] == 0 || labels[start] != 0) continue;

    nextLabel += 1;
    var minX = w, maxX = 0, minY = h, maxY = 0, area = 0;

    stack.add(start);
    labels[start] = nextLabel;

    while (stack.isNotEmpty) {
      final index = stack.removeLast();
      final x = index % w;
      final y = index ~/ w;
      area += 1;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final n = ny * w + nx;
          if (mask[n] == 1 && labels[n] == 0) {
            labels[n] = nextLabel;
            stack.add(n);
          }
        }
      }
    }

    if (area < minArea) continue;

    final boxW = maxX - minX + 1;
    final boxH = maxY - minY + 1;

    // Proxy de confianza: qué fracción del bounding box ocupa la mancha. Una
    // presa es un blob compacto; el ruido y las sombras alargadas no lo son.
    final confidence = area / (boxW * boxH);
    if (confidence < 0.75) continue;

    // Paso 4 — recorte con la máscara como canal alpha.
    final sprite = img.Image(width: boxW, height: boxH, numChannels: 4);
    for (var y = 0; y < boxH; y++) {
      for (var x = 0; x < boxW; x++) {
        final srcX = minX + x;
        final srcY = minY + y;
        final belongs = labels[srcY * w + srcX] == nextLabel;
        final p = work.getPixel(srcX, srcY);
        sprite.setPixelRgba(
          x,
          y,
          p.r.toInt(),
          p.g.toInt(),
          p.b.toInt(),
          belongs ? 255 : 0,
        );
      }
    }

    final originalW = (boxW * backScale).round();
    final originalH = (boxH * backScale).round();

    results.add(SegmentedHold(
      imageBytesPNG: img.encodePng(sprite),
      boundingBoxPx: (width: originalW, height: originalH),
      // Paso 5 — categoría sugerida (§1.4).
      suggestedCategory: heuristicCategory(
        widthPx: originalW,
        heightPx: originalH,
        scaleCmPerPx: scaleCmPerPx,
      ),
      confidence: confidence,
    ));
  }

  // De arriba abajo y de izquierda a derecha: el orden en que el usuario
  // espera revisarlas en la rejilla.
  results.sort((a, b) => b.boundingBoxPx.width
      .compareTo(a.boundingBoxPx.width));
  return results;
}
