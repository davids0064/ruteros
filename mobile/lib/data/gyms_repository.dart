import '../core/api/api_client.dart';
import '../models/enums.dart';
import '../models/gym.dart';

/// Módulos Boulder Gyms y Membresías — 04 §2.4 y §2.5.
class GymsRepository {
  const GymsRepository(this._api);

  final ApiClient _api;

  Future<BoulderGym> create({
    required String name,
    required String address,
    required String city,
    required String country,
    String? phone,
    String? email,
    Map<String, dynamic>? pricingPlans,
    String? logoUrl,
  }) =>
      _api.post('/gyms', (b) => BoulderGym.fromJson(asMap(b)), body: {
        'name': name,
        'address': address,
        'city': city,
        'country': country,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (email != null && email.isNotEmpty) 'email': email,
        'pricingPlans': ?pricingPlans,
        'logoUrl': ?logoUrl,
      });

  Future<List<BoulderGym>> search({String? city, String? country, String? q}) =>
      _api.get(
        '/gyms',
        (b) => parseList(b, BoulderGym.fromJson),
        authenticated: false,
        query: {'city': city, 'country': country, 'q': q},
      );

  Future<BoulderGym> findOne(String gymId) => _api.get(
        '/gyms/$gymId',
        (b) => BoulderGym.fromJson(asMap(b)),
        authenticated: false,
      );

  Future<BoulderGym> update(String gymId, Map<String, dynamic> patch) =>
      _api.patch('/gyms/$gymId', (b) => BoulderGym.fromJson(asMap(b)),
          body: patch);

  // --- Membresías (§2.5) -----------------------------------------------------

  /// Sin `userId` es una autopostulación: queda `pending` hasta que un admin
  /// del boulder la autorice.
  Future<GymSetter> requestMembership(String gymId, {String? userId}) =>
      _api.post(
        '/gyms/$gymId/setters',
        (b) => GymSetter.fromJson(asMap(b)),
        body: {'userId': ?userId},
      );

  Future<List<GymSetter>> setters(String gymId, {MembershipStatus? status}) =>
      _api.get(
        '/gyms/$gymId/setters',
        (b) => parseList(b, GymSetter.fromJson),
        query: {'status': status?.wire},
      );

  Future<GymSetter> updateMembership(
    String gymId,
    String setterId, {
    MembershipStatus? status,
    bool? isGymAdmin,
  }) =>
      _api.patch(
        '/gyms/$gymId/setters/$setterId',
        (b) => GymSetter.fromJson(asMap(b)),
        body: {
          'status': ?status?.wire,
          'isGymAdmin': ?isGymAdmin,
        },
      );
}
