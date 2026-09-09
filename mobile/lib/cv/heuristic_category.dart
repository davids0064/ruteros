import '../models/enums.dart';

/// Heurística de categoría — 04_COMPONENT_SPECS.md §1.4.
///
/// Clasificación provisional en cliente, **siempre editable por el usuario**
/// antes de confirmar el alta. El orden de las reglas es significativo: la
/// especificación las evalúa en cascada, y la primera que se cumple gana.
///
/// ```
/// area_cm2  = (width_px * height_px) * (scale_cm_per_px ^ 2)
/// aspect    = width_px / height_px
///
/// area_cm2 > 400                     -> 'volume'
/// area_cm2 < 25                      -> 'foothold'
/// aspect   > 2.5 && height_px < 40   -> 'crimp'
/// aspect   < 0.6                     -> 'pinch'
/// area_cm2 > 150                     -> 'jug'
/// otro                               -> 'sloper'
/// ```
HoldCategory heuristicCategory({
  required int widthPx,
  required int heightPx,
  required double scaleCmPerPx,
}) {
  final areaCm2 = widthPx * heightPx * scaleCmPerPx * scaleCmPerPx;
  final aspect = widthPx / heightPx;

  if (areaCm2 > 400) return HoldCategory.volume;
  if (areaCm2 < 25) return HoldCategory.foothold;
  if (aspect > 2.5 && heightPx < 40) return HoldCategory.crimp;
  if (aspect < 0.6) return HoldCategory.pinch;
  if (areaCm2 > 150) return HoldCategory.jug;
  return HoldCategory.sloper;
}

/// Peso intrínseco sugerido para `holds.difficulty_rating_weight`.
///
/// Alimenta el motor de dificultad (§6), cuyos `weight_factor` de referencia
/// van de 1.0 (V0) a 4.8 (V8) según la Matriz del PRD §7. Un bidón es el agarre
/// fácil por definición; una regleta, el difícil.
double suggestedWeight(HoldCategory category) => switch (category) {
      HoldCategory.jug => 1.0,
      HoldCategory.volume => 1.2,
      HoldCategory.foothold => 1.0,
      HoldCategory.pinch => 2.4,
      HoldCategory.sloper => 3.2,
      HoldCategory.crimp => 4.0,
    };
