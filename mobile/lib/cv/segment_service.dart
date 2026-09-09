import 'dart:typed_data';

import '../models/enums.dart';

/// `SegmentedHoldResult` — 04 §1.2.
///
/// Vive en RAM: nunca se escribe a disco (RNF-1). El PNG se sube a S3 y sólo su
/// URL llega a PostgreSQL (§1.3).
class SegmentedHold {
  const SegmentedHold({
    required this.imageBytesPNG,
    required this.boundingBoxPx,
    required this.suggestedCategory,
    required this.confidence,
  });

  /// Imagen recortada con canal alpha (fondo transparente).
  final Uint8List imageBytesPNG;
  final ({int width, int height}) boundingBoxPx;
  final HoldCategory suggestedCategory;

  /// 04 §1.2 descarta las detecciones por debajo de 0.75.
  final double confidence;
}

/// Contrato del servicio — 04 §1.1.
///
/// * **Entrada:** fotografía del set (JPG/PNG) y el `colorHex` del set.
/// * **Salida:** sprites recortados con fondo transparente y sus metadatos,
///   en memoria.
abstract interface class SegmentService {
  Future<List<SegmentedHold>> processSetImage({
    required Uint8List imageBytes,
    required String colorHex,
    double scaleCmPerPx,
  });
}
