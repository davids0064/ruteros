/// `GradeValueDTO` — 04 §2.6.
class GradeValue {
  const GradeValue({
    required this.id,
    required this.systemId,
    required this.levelLabel,
    required this.rankOrdinal,
    required this.weightFactor,
  });

  final String id;
  final String systemId;
  final String levelLabel;
  final int rankOrdinal;
  final double weightFactor;

  factory GradeValue.fromJson(Map<String, dynamic> json) => GradeValue(
        id: json['id'] as String,
        systemId: json['systemId'] as String,
        levelLabel: json['levelLabel'] as String,
        rankOrdinal: (json['rankOrdinal'] as num).toInt(),
        weightFactor: (json['weightFactor'] as num).toDouble(),
      );
}

/// `GradeSystemDTO` — 04 §2.6. `gymId` nulo => sistema global.
class GradeSystem {
  const GradeSystem({
    required this.id,
    required this.name,
    required this.values,
    this.gymId,
    this.description,
  });

  final String id;
  final String name;
  final List<GradeValue> values;
  final String? gymId;
  final String? description;

  bool get isGlobal => gymId == null;

  factory GradeSystem.fromJson(Map<String, dynamic> json) => GradeSystem(
        id: json['id'] as String,
        gymId: json['gymId'] as String?,
        name: json['name'] as String,
        description: json['description'] as String?,
        values: (json['values'] as List<dynamic>? ?? const [])
            .map((e) => GradeValue.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
