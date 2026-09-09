import 'package:boulder_cosetter/cv/heuristic_category.dart';
import 'package:boulder_cosetter/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// 04_COMPONENT_SPECS.md §1.4 — la cascada de reglas, regla a regla.
void main() {
  group('heuristicCategory', () {
    // A 0.25 cm/px, 1 px² = 0.0625 cm².
    const scale = 0.25;

    test('area_cm2 > 400 -> volume', () {
      // 90 x 90 px = 8100 px² = 506.25 cm²
      expect(
        heuristicCategory(widthPx: 90, heightPx: 90, scaleCmPerPx: scale),
        HoldCategory.volume,
      );
    });

    test('area_cm2 < 25 -> foothold', () {
      // 18 x 18 px = 324 px² = 20.25 cm²
      expect(
        heuristicCategory(widthPx: 18, heightPx: 18, scaleCmPerPx: scale),
        HoldCategory.foothold,
      );
    });

    test('volume gana a foothold: el orden de la cascada importa', () {
      // Un bloque enorme nunca puede clasificarse como presa de pie.
      expect(
        heuristicCategory(widthPx: 200, heightPx: 200, scaleCmPerPx: scale),
        HoldCategory.volume,
      );
    });

    test('aspect > 2.5 y height < 40 -> crimp', () {
      // 100 x 30 px: aspect 3.33, area 187.5 cm²
      expect(
        heuristicCategory(widthPx: 100, heightPx: 30, scaleCmPerPx: scale),
        HoldCategory.crimp,
      );
    });

    test('una regleta alta no es crimp: la altura manda', () {
      // aspect 3.0 pero height 50 -> cae a la siguiente regla que aplique
      expect(
        heuristicCategory(widthPx: 150, heightPx: 50, scaleCmPerPx: scale),
        isNot(HoldCategory.crimp),
      );
    });

    test('aspect < 0.6 -> pinch', () {
      // 30 x 80 px: aspect 0.375, area 150 cm² (no supera el umbral de jug)
      expect(
        heuristicCategory(widthPx: 30, heightPx: 80, scaleCmPerPx: scale),
        HoldCategory.pinch,
      );
    });

    test('area_cm2 > 150 -> jug', () {
      // 70 x 60 px = 4200 px² = 262.5 cm², aspect 1.17
      expect(
        heuristicCategory(widthPx: 70, heightPx: 60, scaleCmPerPx: scale),
        HoldCategory.jug,
      );
    });

    test('el resto -> sloper', () {
      // 50 x 50 px = 2500 px² = 156.25 cm²... justo por encima de 150 -> jug.
      // 45 x 45 px = 2025 px² = 126.56 cm², aspect 1 -> sloper.
      expect(
        heuristicCategory(widthPx: 45, heightPx: 45, scaleCmPerPx: scale),
        HoldCategory.sloper,
      );
    });

    test('la escala cambia el veredicto sin cambiar los píxeles', () {
      const w = 60, h = 60;
      expect(
        heuristicCategory(widthPx: w, heightPx: h, scaleCmPerPx: 0.05),
        HoldCategory.foothold, // 9 cm²
      );
      expect(
        heuristicCategory(widthPx: w, heightPx: h, scaleCmPerPx: 0.6),
        HoldCategory.volume, // 1296 cm²
      );
    });
  });

  group('suggestedWeight', () {
    test('cubre todas las categorías y se mantiene en el rango de la escala', () {
      for (final category in HoldCategory.values) {
        final weight = suggestedWeight(category);
        expect(weight, greaterThan(0));
        // La Matriz Referencial del PRD §7 va de 1.0 (V0) a 4.8 (V8).
        expect(weight, lessThanOrEqualTo(4.8));
      }
    });

    test('una regleta pesa más que un bidón', () {
      expect(suggestedWeight(HoldCategory.crimp),
          greaterThan(suggestedWeight(HoldCategory.jug)));
    });
  });
}
