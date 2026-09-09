import 'enums.dart';

/// `HoldSetDTO` — 04 §2.8.
class HoldSet {
  const HoldSet({
    required this.id,
    required this.gymId,
    required this.name,
    required this.colorHex,
    required this.holdsCount,
    required this.availableCount,
    this.creatorId,
  });

  final String id;
  final String gymId;
  final String name;
  final String colorHex;
  final int holdsCount;
  final int availableCount;
  final String? creatorId;

  factory HoldSet.fromJson(Map<String, dynamic> json) => HoldSet(
        id: json['id'] as String,
        gymId: json['gymId'] as String,
        creatorId: json['creatorId'] as String?,
        name: json['name'] as String,
        colorHex: json['colorHex'] as String,
        holdsCount: (json['holdsCount'] as num).toInt(),
        availableCount: (json['availableCount'] as num).toInt(),
      );
}

class BoundingBox {
  const BoundingBox({required this.widthPx, required this.heightPx});

  final int widthPx;
  final int heightPx;

  double get aspect => widthPx / heightPx;

  /// 04 §3: la clave viaja en snake_case dentro del JSONB, tal cual la fija
  /// `03_DATA_MODELS.md` (`{ "width_px": 120, "height_px": 80 }`).
  factory BoundingBox.fromJson(Map<String, dynamic> json) => BoundingBox(
        widthPx: (json['width_px'] as num).toInt(),
        heightPx: (json['height_px'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {'width_px': widthPx, 'height_px': heightPx};
}

/// `HoldDTO` — 04 §2.8.
class Hold {
  const Hold({
    required this.id,
    required this.setId,
    required this.imageCropUrl,
    required this.typeCategory,
    required this.status,
    required this.difficultyRatingWeight,
    this.boundingBoxData,
  });

  final String id;
  final String setId;
  final String imageCropUrl;
  final HoldCategory typeCategory;

  /// Nunca lo fija el cliente: lo gobiernan los triggers (RF-2.3).
  final HoldStatus status;
  final double difficultyRatingWeight;
  final BoundingBox? boundingBoxData;

  factory Hold.fromJson(Map<String, dynamic> json) => Hold(
        id: json['id'] as String,
        setId: json['setId'] as String,
        imageCropUrl: json['imageCropUrl'] as String,
        typeCategory: HoldCategory.fromWire(json['typeCategory'] as String),
        status: HoldStatus.fromWire(json['status'] as String),
        difficultyRatingWeight:
            (json['difficultyRatingWeight'] as num).toDouble(),
        boundingBoxData: json['boundingBoxData'] == null
            ? null
            : BoundingBox.fromJson(
                Map<String, dynamic>.from(json['boundingBoxData'] as Map)),
      );
}

/// `CreateHoldPayload` — 04 §2.8. `status` se omite a propósito: la BD aplica
/// el default `available` (§1.3).
class CreateHoldPayload {
  const CreateHoldPayload({
    required this.imageCropUrl,
    required this.typeCategory,
    this.difficultyRatingWeight,
    this.boundingBoxData,
  });

  final String imageCropUrl;
  final HoldCategory typeCategory;
  final double? difficultyRatingWeight;
  final BoundingBox? boundingBoxData;

  Map<String, dynamic> toJson() => {
        'imageCropUrl': imageCropUrl,
        'typeCategory': typeCategory.wire,
        if (difficultyRatingWeight != null)
          'difficultyRatingWeight': difficultyRatingWeight,
        if (boundingBoxData != null) 'boundingBoxData': boundingBoxData!.toJson(),
      };
}
