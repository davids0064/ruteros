/// `WallDTO` — 04 §2.7 (RF-3.1, US-03).
class Wall {
  const Wall({
    required this.id,
    required this.gymId,
    required this.name,
    required this.photoUrl,
    required this.widthCm,
    required this.heightCm,
    required this.defaultInclineDeg,
    required this.isPublic,
    required this.activeRoutesCount,
    this.creatorId,
    this.defaultGradeSystemId,
  });

  final String id;
  final String gymId;
  final String name;
  final String photoUrl;
  final double widthCm;
  final double heightCm;

  /// theta capturado con el giroscopio al registrar el muro.
  final double defaultInclineDeg;
  final bool isPublic;
  final int activeRoutesCount;
  final String? creatorId;
  final String? defaultGradeSystemId;

  /// Relación de aspecto física del muro: el lienzo 2D la respeta para que las
  /// coordenadas porcentuales no se deformen.
  double get aspectRatio => widthCm / heightCm;

  factory Wall.fromJson(Map<String, dynamic> json) => Wall(
        id: json['id'] as String,
        gymId: json['gymId'] as String,
        creatorId: json['creatorId'] as String?,
        name: json['name'] as String,
        photoUrl: json['photoUrl'] as String,
        widthCm: (json['widthCm'] as num).toDouble(),
        heightCm: (json['heightCm'] as num).toDouble(),
        defaultInclineDeg: (json['defaultInclineDeg'] as num).toDouble(),
        defaultGradeSystemId: json['defaultGradeSystemId'] as String?,
        isPublic: json['isPublic'] as bool,
        activeRoutesCount: (json['activeRoutesCount'] as num).toInt(),
      );
}
