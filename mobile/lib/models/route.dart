import 'enums.dart';
import 'grade.dart';
import 'hold.dart';

/// `PlacedHoldDTO` — 03_DATA_MODELS.md, sin alteraciones.
///
/// 04 §3, excepción explícita: `placed_holds.hold_role` se serializa como
/// `role`, **no** como `holdRole`.
class PlacedHold {
  const PlacedHold({
    required this.holdId,
    required this.xPercent,
    required this.yPercent,
    required this.rotationDeg,
    required this.role,
    this.id,
  });

  final String? id;
  final String holdId;
  final double xPercent;
  final double yPercent;
  final int rotationDeg;
  final HoldRole role;

  PlacedHold copyWith({
    double? xPercent,
    double? yPercent,
    int? rotationDeg,
    HoldRole? role,
  }) =>
      PlacedHold(
        id: id,
        holdId: holdId,
        xPercent: xPercent ?? this.xPercent,
        yPercent: yPercent ?? this.yPercent,
        rotationDeg: rotationDeg ?? this.rotationDeg,
        role: role ?? this.role,
      );

  factory PlacedHold.fromJson(Map<String, dynamic> json) => PlacedHold(
        id: json['id'] as String?,
        holdId: json['holdId'] as String,
        xPercent: (json['xPercent'] as num).toDouble(),
        yPercent: (json['yPercent'] as num).toDouble(),
        rotationDeg: (json['rotationDeg'] as num).toInt(),
        role: HoldRole.fromWire(json['role'] as String),
      );

  /// El `id` no se envía: en un reemplazo total el servidor recrea las filas.
  Map<String, dynamic> toJson() => {
        'holdId': holdId,
        'xPercent': xPercent,
        'yPercent': yPercent,
        'rotationDeg': rotationDeg,
        'role': role.wire,
      };
}

/// Una presa colocada junto a su sprite, tal como la devuelve `RouteDetailDTO`.
class PlacedHoldWithSprite {
  const PlacedHoldWithSprite({required this.placement, required this.hold});

  final PlacedHold placement;
  final Hold hold;

  factory PlacedHoldWithSprite.fromJson(Map<String, dynamic> json) =>
      PlacedHoldWithSprite(
        placement: PlacedHold.fromJson(json),
        hold: Hold.fromJson(json['hold'] as Map<String, dynamic>),
      );
}

class RouteCreator {
  const RouteCreator({required this.id, required this.username, this.avatarUrl});

  final String id;
  final String username;
  final String? avatarUrl;

  factory RouteCreator.fromJson(Map<String, dynamic> json) => RouteCreator(
        id: json['id'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
      );
}

/// `RouteSummaryDTO` — 04 §2.9 (US-07: la autoría es visible).
class RouteSummary {
  const RouteSummary({
    required this.id,
    required this.wallId,
    required this.title,
    required this.status,
    required this.wallInclineDeg,
    required this.targetGrade,
    required this.creator,
    required this.holdsCount,
    required this.createdAt,
    this.calculatedGrade,
    this.dismantledAt,
  });

  final String id;
  final String wallId;
  final String title;
  final RouteStatus status;
  final double wallInclineDeg;
  final GradeValue targetGrade;
  final GradeValue? calculatedGrade;
  final RouteCreator creator;
  final int holdsCount;
  final DateTime createdAt;
  final DateTime? dismantledAt;

  factory RouteSummary.fromJson(Map<String, dynamic> json) => RouteSummary(
        id: json['id'] as String,
        wallId: json['wallId'] as String,
        title: json['title'] as String,
        status: RouteStatus.fromWire(json['status'] as String),
        wallInclineDeg: (json['wallInclineDeg'] as num).toDouble(),
        targetGrade:
            GradeValue.fromJson(json['targetGrade'] as Map<String, dynamic>),
        calculatedGrade: json['calculatedGrade'] == null
            ? null
            : GradeValue.fromJson(
                json['calculatedGrade'] as Map<String, dynamic>),
        creator: RouteCreator.fromJson(json['creator'] as Map<String, dynamic>),
        holdsCount: (json['holdsCount'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        dismantledAt: json['dismantledAt'] == null
            ? null
            : DateTime.parse(json['dismantledAt'] as String),
      );
}

/// `RouteDetailDTO` — 04 §2.9. El sprite viene embebido: el canvas pinta sin
/// un segundo viaje al backend.
class RouteDetail extends RouteSummary {
  const RouteDetail({
    required super.id,
    required super.wallId,
    required super.title,
    required super.status,
    required super.wallInclineDeg,
    required super.targetGrade,
    required super.creator,
    required super.holdsCount,
    required super.createdAt,
    required this.placedHolds,
    super.calculatedGrade,
    super.dismantledAt,
  });

  final List<PlacedHoldWithSprite> placedHolds;

  factory RouteDetail.fromJson(Map<String, dynamic> json) {
    final summary = RouteSummary.fromJson(json);
    return RouteDetail(
      id: summary.id,
      wallId: summary.wallId,
      title: summary.title,
      status: summary.status,
      wallInclineDeg: summary.wallInclineDeg,
      targetGrade: summary.targetGrade,
      calculatedGrade: summary.calculatedGrade,
      creator: summary.creator,
      holdsCount: summary.holdsCount,
      createdAt: summary.createdAt,
      dismantledAt: summary.dismantledAt,
      placedHolds: (json['placedHolds'] as List<dynamic>? ?? const [])
          .map((e) =>
              PlacedHoldWithSprite.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// `GenerateRouteProposal` — 04 §2.9. No persiste nada.
class RouteProposal {
  const RouteProposal({
    required this.placedHolds,
    required this.estimatedGradeId,
    required this.rationale,
  });

  final List<PlacedHold> placedHolds;
  final String estimatedGradeId;
  final String rationale;

  factory RouteProposal.fromJson(Map<String, dynamic> json) => RouteProposal(
        placedHolds: (json['placedHolds'] as List<dynamic>)
            .map((e) => PlacedHold.fromJson(e as Map<String, dynamic>))
            .toList(),
        estimatedGradeId: json['estimatedGradeId'] as String,
        rationale: json['rationale'] as String,
      );
}
