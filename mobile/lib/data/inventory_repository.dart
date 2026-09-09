import '../core/api/api_client.dart';
import '../models/enums.dart';
import '../models/hold.dart';

/// Módulo Inventario — 04 §2.8 (RF-2.1, RF-2.2, RF-2.3).
class InventoryRepository {
  const InventoryRepository(this._api);

  final ApiClient _api;

  Future<HoldSet> createSet(
    String gymId, {
    required String name,
    required String colorHex,
  }) =>
      _api.post('/gyms/$gymId/hold-sets', (b) => HoldSet.fromJson(asMap(b)),
          body: {'name': name, 'colorHex': colorHex});

  Future<List<HoldSet>> sets(String gymId, {String? colorHex}) => _api.get(
        '/gyms/$gymId/hold-sets',
        (b) => parseList(b, HoldSet.fromJson),
        query: {'colorHex': colorHex},
      );

  /// Alta masiva transaccional tras la segmentación (KPI: 10 presas < 15 s).
  Future<List<Hold>> createHolds(String setId, List<CreateHoldPayload> holds) =>
      _api.post(
        '/hold-sets/$setId/holds/batch',
        (b) => parseList(b, Hold.fromJson),
        body: {'holds': [for (final h in holds) h.toJson()]},
      );

  Future<List<Hold>> holdsOfSet(String setId, {HoldStatus? status}) => _api.get(
        '/hold-sets/$setId/holds',
        (b) => parseList(b, Hold.fromJson),
        query: {'status': status?.wire},
      );

  /// RNF-3: alimenta el editor de canvas en < 500 ms.
  Future<List<Hold>> available(String gymId, {List<String>? setIds}) => _api.get(
        '/gyms/$gymId/holds/available',
        (b) => parseList(b, Hold.fromJson),
        query: {'setIds': setIds?.isEmpty ?? true ? null : setIds!.join(',')},
      );

  /// La API rechaza `in_use`: esa transición es potestad de los triggers.
  Future<Hold> updateHold(
    String holdId, {
    HoldCategory? typeCategory,
    double? difficultyRatingWeight,
    HoldStatus? status,
  }) {
    assert(status == null || HoldStatus.clientSettable.contains(status),
        'El estado in_use lo gobierna la base de datos, no el cliente.');
    return _api.patch('/holds/$holdId', (b) => Hold.fromJson(asMap(b)), body: {
      'typeCategory': ?typeCategory?.wire,
      'difficultyRatingWeight': ?difficultyRatingWeight,
      'status': ?status?.wire,
    });
  }
}
