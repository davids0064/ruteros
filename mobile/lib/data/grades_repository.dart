import '../core/api/api_client.dart';
import '../models/grade.dart';

/// Módulo Sistemas de Grado — 04 §2.6 (RF-3.2).
class GradesRepository {
  const GradesRepository(this._api);

  final ApiClient _api;

  /// Globales, más los del boulder indicado.
  Future<List<GradeSystem>> systems({String? gymId}) => _api.get(
        '/grade-systems',
        (b) => parseList(b, GradeSystem.fromJson),
        authenticated: false,
        query: {'gymId': gymId},
      );

  /// Ordenado por `rankOrdinal` ascendente.
  Future<List<GradeValue>> values(String systemId) => _api.get(
        '/grade-systems/$systemId/values',
        (b) => parseList(b, GradeValue.fromJson),
        authenticated: false,
      );

  Future<GradeSystem> createSystem(
    String gymId, {
    required String name,
    required List<GradeValue> values,
    String? description,
  }) =>
      _api.post(
        '/gyms/$gymId/grade-systems',
        (b) => GradeSystem.fromJson(asMap(b)),
        body: {
          'name': name,
          'description': ?description,
          'values': [
            for (final v in values)
              {
                'levelLabel': v.levelLabel,
                'rankOrdinal': v.rankOrdinal,
                'weightFactor': v.weightFactor,
              }
          ],
        },
      );
}
