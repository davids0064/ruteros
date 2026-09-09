import '../core/api/api_client.dart';
import '../models/enums.dart';
import '../models/route.dart';

/// Módulo Rutas — 04 §2.9 (RF-4.2, RF-4.3, US-05, US-07).
class RoutesRepository {
  const RoutesRepository(this._api);

  final ApiClient _api;

  /// No persiste nada: la propuesta vive en RAM hasta que el setter publica.
  Future<RouteProposal> generate({
    required String wallId,
    required String gradeSystemId,
    required String targetGradeId,
    required double wallInclineDeg,
    required List<String> enabledSetIds,
    int? holdCount,
  }) =>
      _api.post('/routes/generate', (b) => RouteProposal.fromJson(asMap(b)),
          body: {
            'wallId': wallId,
            'gradeSystemId': gradeSystemId,
            'targetGradeId': targetGradeId,
            'wallInclineDeg': wallInclineDeg,
            'enabledSetIds': enabledSetIds,
            'holdCount': ?holdCount,
          });

  /// `creatorId` viaja por contrato, pero el servidor usa el `sub` del JWT.
  Future<RouteDetail> publish({
    required String wallId,
    required String creatorId,
    required String title,
    required String targetGradeId,
    required double wallInclineDeg,
    required List<PlacedHold> placedHolds,
  }) =>
      _api.post('/routes', (b) => RouteDetail.fromJson(asMap(b)), body: {
        'wallId': wallId,
        'creatorId': creatorId,
        'title': title,
        'targetGradeId': targetGradeId,
        'wallInclineDeg': wallInclineDeg,
        'placedHolds': [for (final p in placedHolds) p.toJson()],
      });

  Future<List<RouteSummary>> byWall(
    String wallId, {
    RouteStatus? status,
    String? creatorId,
    String? gradeId,
  }) =>
      _api.get(
        '/walls/$wallId/routes',
        (b) => parseList(b, RouteSummary.fromJson),
        authenticated: false,
        query: {
          'status': status?.wire,
          'creatorId': creatorId,
          'gradeId': gradeId,
        },
      );

  Future<RouteDetail> detail(String routeId) => _api.get(
        '/routes/$routeId',
        (b) => RouteDetail.fromJson(asMap(b)),
        authenticated: false,
      );

  Future<RouteDetail> update(
    String routeId, {
    String? title,
    String? targetGradeId,
    RouteStatus? status,
    List<PlacedHold>? placedHolds,
  }) {
    assert(status != RouteStatus.archivedDismantled,
        'El desmontaje va por POST /routes/:id/dismantle.');
    return _api.patch('/routes/$routeId', (b) => RouteDetail.fromJson(asMap(b)),
        body: {
          'title': ?title,
          'targetGradeId': ?targetGradeId,
          'status': ?status?.wire,
          if (placedHolds != null)
            'placedHolds': [for (final p in placedHolds) p.toJson()],
        });
  }

  /// Libera las presas vía trigger (04 §2.9.2).
  Future<RouteDetail> dismantle(String routeId) => _api.post(
        '/routes/$routeId/dismantle',
        (b) => RouteDetail.fromJson(asMap(b)),
      );
}
