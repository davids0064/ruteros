import 'enums.dart';

/// `GymMembershipDTO` — 04 §2.3.
class GymMembership {
  const GymMembership({
    required this.gymId,
    required this.gymName,
    required this.status,
    required this.isGymAdmin,
  });

  final String gymId;
  final String gymName;
  final MembershipStatus status;
  final bool isGymAdmin;

  bool get isAuthorized => status == MembershipStatus.authorized;

  factory GymMembership.fromJson(Map<String, dynamic> json) => GymMembership(
        gymId: json['gymId'] as String,
        gymName: json['gymName'] as String,
        status: MembershipStatus.fromWire(json['status'] as String),
        isGymAdmin: json['isGymAdmin'] as bool,
      );
}

/// `UserProfileDTO` — 04 §2.3.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.memberships,
    this.displayName,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String username;
  final UserRole role;
  final List<GymMembership> memberships;
  final String? displayName;
  final String? avatarUrl;

  String get shownName => displayName ?? username;

  /// KPI multi-boulder: sólo los boulders donde el setter está autorizado.
  List<GymMembership> get authorizedGyms =>
      memberships.where((m) => m.isAuthorized).toList();

  bool isAdminOf(String gymId) => memberships.any(
      (m) => m.gymId == gymId && m.isAuthorized && m.isGymAdmin);

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        role: UserRole.fromWire(json['role'] as String),
        displayName: json['displayName'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        memberships: (json['memberships'] as List<dynamic>? ?? const [])
            .map((e) => GymMembership.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// `AuthSessionDTO` — 04 §2.3.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final UserProfile user;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: (json['expiresIn'] as num).toInt(),
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}
