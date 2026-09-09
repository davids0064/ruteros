import '../core/api/api_client.dart';
import '../models/wall.dart';

/// Módulo Muros — 04 §2.7 (RF-3.1, US-03).
class WallsRepository {
  const WallsRepository(this._api);

  final ApiClient _api;

  Future<Wall> create(
    String gymId, {
    required String name,
    required String photoUrl,
    required double widthCm,
    required double heightCm,
    required double defaultInclineDeg,
    String? defaultGradeSystemId,
    bool isPublic = false,
  }) =>
      _api.post('/gyms/$gymId/walls', (b) => Wall.fromJson(asMap(b)), body: {
        'name': name,
        'photoUrl': photoUrl,
        'widthCm': widthCm,
        'heightCm': heightCm,
        'defaultInclineDeg': defaultInclineDeg,
        'defaultGradeSystemId': ?defaultGradeSystemId,
        'isPublic': isPublic,
      });

  Future<List<Wall>> byGym(String gymId) =>
      _api.get('/gyms/$gymId/walls', (b) => parseList(b, Wall.fromJson));

  Future<Wall> findOne(String wallId) => _api.get(
        '/walls/$wallId',
        (b) => Wall.fromJson(asMap(b)),
        authenticated: false,
      );

  Future<Wall> update(String wallId, Map<String, dynamic> patch) =>
      _api.patch('/walls/$wallId', (b) => Wall.fromJson(asMap(b)), body: patch);
}
