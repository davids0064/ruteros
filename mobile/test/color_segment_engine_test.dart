import 'dart:typed_data';

import 'package:boulder_cosetter/cv/color_segment_engine.dart';
import 'package:boulder_cosetter/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Fotografía sintética de un set: fondo liso y N presas del color del set.
Uint8List _syntheticSetPhoto({
  required List<({int x, int y, int w, int h})> holds,
  required int color,
  int width = 800,
  int height = 600,
}) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  // Fondo gris muy claro, como una lona o un suelo de gimnasio.
  img.fill(image, color: img.ColorUint8.rgba(245, 245, 245, 255));

  final r = color & 0xFF;
  final g = (color >> 8) & 0xFF;
  final b = (color >> 16) & 0xFF;

  for (final hold in holds) {
    img.fillRect(
      image,
      x1: hold.x,
      y1: hold.y,
      x2: hold.x + hold.w - 1,
      y2: hold.y + hold.h - 1,
      color: img.ColorUint8.rgba(r, g, b, 255),
    );
  }
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  const engine = ColorSegmentEngine();

  group('parseHexColor', () {
    test('acepta con y sin almohadilla', () {
      expect(parseHexColor('#FFD700'), (r: 255, g: 215, b: 0));
      expect(parseHexColor('FFD700'), (r: 255, g: 215, b: 0));
    });

    test('rechaza un formato inválido', () {
      expect(() => parseHexColor('amarillo'), throwsFormatException);
      expect(() => parseHexColor('#FFF'), throwsFormatException);
    });
  });

  group('colorDistance', () {
    test('vale 0 para el mismo color', () {
      expect(colorDistance(255, 215, 0, 255, 215, 0), 0);
    });

    test('crece con la diferencia y se mantiene normalizada', () {
      final cercano = colorDistance(255, 215, 0, 250, 210, 5);
      final lejano = colorDistance(255, 215, 0, 0, 0, 255);
      expect(cercano, lessThan(lejano));
      expect(lejano, inInclusiveRange(0, 1));
    });
  });

  group('processSetImage (04 §1.2)', () {
    test('aísla cada presa del color del set', () async {
      // Amarillo #FFD700 -> en el orden ABGR de `image`: 0x0000D7FF
      final photo = _syntheticSetPhoto(
        color: 0x0000D7FF,
        holds: [
          (x: 60, y: 60, w: 120, h: 120),
          (x: 300, y: 150, w: 160, h: 90),
          (x: 560, y: 380, w: 100, h: 100),
        ],
      );

      final results = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
      );

      expect(results, hasLength(3));
      for (final hold in results) {
        expect(hold.imageBytesPNG, isNotEmpty);
        expect(hold.confidence, greaterThanOrEqualTo(0.75));
        expect(hold.boundingBoxPx.width, greaterThan(0));
        expect(hold.boundingBoxPx.height, greaterThan(0));
      }
    });

    test('el recorte lleva canal alpha: fuera de la presa es transparente',
        () async {
      final photo = _syntheticSetPhoto(
        color: 0x0000D7FF,
        holds: [(x: 200, y: 200, w: 160, h: 160)],
      );

      final results = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
      );

      final sprite = img.decodePng(results.single.imageBytesPNG)!;
      expect(sprite.numChannels, 4);
      // Centro opaco (es la presa).
      expect(sprite.getPixel(sprite.width ~/ 2, sprite.height ~/ 2).a, 255);
    });

    test('ignora las presas de otro color: el filtro es el del set', () async {
      final photo = _syntheticSetPhoto(
        color: 0x000000FF, // rojo puro
        holds: [(x: 100, y: 100, w: 140, h: 140)],
      );

      final amarillas = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
      );
      expect(amarillas, isEmpty);

      final rojas = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FF0000',
      );
      expect(rojas, hasLength(1));
    });

    test('descarta el ruido por debajo del área mínima', () async {
      final photo = _syntheticSetPhoto(
        color: 0x0000D7FF,
        holds: [
          (x: 100, y: 100, w: 160, h: 160), // presa
          (x: 500, y: 500, w: 2, h: 2), // mota de polvo
        ],
      );

      final results = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
      );
      expect(results, hasLength(1));
    });

    test('el bounding box se reporta en píxeles de la imagen original',
        () async {
      // 1600x1200 se reduce a 640x480 para trabajar, pero el bbox debe volver
      // a la escala original: es lo que hace comparable `scale_cm_per_px`.
      final photo = _syntheticSetPhoto(
        width: 1600,
        height: 1200,
        color: 0x0000D7FF,
        holds: [(x: 400, y: 400, w: 400, h: 400)],
      );

      final results = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
      );

      // 400 px con un 5% de holgura por el remuestreo.
      expect(results.single.boundingBoxPx.width, closeTo(400, 20));
      expect(results.single.boundingBoxPx.height, closeTo(400, 20));
    });

    test('sugiere categoría con la heurística de §1.4', () async {
      final photo = _syntheticSetPhoto(
        color: 0x0000D7FF,
        holds: [(x: 100, y: 100, w: 300, h: 300)], // grande -> volumen
      );

      final results = await engine.processSetImage(
        imageBytes: photo,
        colorHex: '#FFD700',
        scaleCmPerPx: 0.25,
      );
      expect(results.single.suggestedCategory, HoldCategory.volume);
    });

    test('una imagen ilegible devuelve lista vacía en lugar de reventar',
        () async {
      final results = await engine.processSetImage(
        imageBytes: Uint8List.fromList([0, 1, 2, 3]),
        colorHex: '#FFD700',
      );
      expect(results, isEmpty);
    });
  });
}
