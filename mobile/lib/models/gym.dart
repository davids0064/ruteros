import 'enums.dart';

/// `BoulderGymDTO` — 03_DATA_MODELS.md, sin alteraciones.
class BoulderGym {
  const BoulderGym({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.country,
    required this.pricingPlans,
    this.phone,
    this.email,
    this.logoUrl,
  });

  final String id;
  final String name;
  final String address;
  final String city;
  final String country;
  final Map<String, dynamic> pricingPlans;
  final String? phone;
  final String? email;
  final String? logoUrl;

  factory BoulderGym.fromJson(Map<String, dynamic> json) => BoulderGym(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String,
        city: json['city'] as String,
        country: json['country'] as String,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        logoUrl: json['logoUrl'] as String?,
        pricingPlans:
            Map<String, dynamic>.from(json['pricingPlans'] as Map? ?? const {}),
      );
}

/// `GymSetterDTO` — 04 §2.5.
class GymSetter {
  const GymSetter({
    required this.id,
    required this.gymId,
    required this.userId,
    required this.username,
    required this.status,
    required this.isGymAdmin,
    required this.createdAt,
    this.displayName,
    this.avatarUrl,
    this.authorizedBy,
    this.authorizedAt,
  });

  final String id;
  final String gymId;
  final String userId;
  final String username;
  final MembershipStatus status;
  final bool isGymAdmin;
  final DateTime createdAt;
  final String? displayName;
  final String? avatarUrl;
  final String? authorizedBy;
  final DateTime? authorizedAt;

  String get shownName => displayName ?? username;

  factory GymSetter.fromJson(Map<String, dynamic> json) => GymSetter(
        id: json['id'] as String,
        gymId: json['gymId'] as String,
        userId: json['userId'] as String,
        username: json['username'] as String,
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        status: MembershipStatus.fromWire(json['status'] as String),
        isGymAdmin: json['isGymAdmin'] as bool,
        authorizedBy: json['authorizedBy'] as String?,
        authorizedAt: json['authorizedAt'] == null
            ? null
            : DateTime.parse(json['authorizedAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
