/// ENUMs del dominio.
///
/// Los valores viajan como los `string` literales de PostgreSQL, sin
/// transformar (`foot_only`, `archived_dismantled`, `in_use`) — 04 §3.
library;

/// `hold_type_enum` — RF-2.2.
enum HoldCategory {
  crimp,
  sloper,
  jug,
  pinch,
  foothold,
  volume;

  static HoldCategory fromWire(String value) =>
      HoldCategory.values.firstWhere((e) => e.name == value);

  String get wire => name;

  String get label => switch (this) {
        HoldCategory.crimp => 'Regleta',
        HoldCategory.sloper => 'Romo',
        HoldCategory.jug => 'Bidón',
        HoldCategory.pinch => 'Pinza',
        HoldCategory.foothold => 'Pie',
        HoldCategory.volume => 'Volumen',
      };
}

/// `hold_status_enum` — RF-2.3.
enum HoldStatus {
  available,
  inUse,
  maintenance,
  retired;

  static const _wire = {
    HoldStatus.available: 'available',
    HoldStatus.inUse: 'in_use',
    HoldStatus.maintenance: 'maintenance',
    HoldStatus.retired: 'retired',
  };

  static HoldStatus fromWire(String value) =>
      _wire.entries.firstWhere((e) => e.value == value).key;

  String get wire => _wire[this]!;

  String get label => switch (this) {
        HoldStatus.available => 'Disponible',
        HoldStatus.inUse => 'En uso',
        HoldStatus.maintenance => 'Mantenimiento',
        HoldStatus.retired => 'Retirada',
      };

  /// 04 §2.8: `in_use` lo gobierna la base de datos, no el cliente.
  static const clientSettable = [
    HoldStatus.available,
    HoldStatus.maintenance,
    HoldStatus.retired,
  ];
}

/// `hold_role_enum` — RF-4.2.
enum HoldRole {
  start,
  hand,
  footOnly,
  top;

  static const _wire = {
    HoldRole.start: 'start',
    HoldRole.hand: 'hand',
    HoldRole.footOnly: 'foot_only',
    HoldRole.top: 'top',
  };

  static HoldRole fromWire(String value) =>
      _wire.entries.firstWhere((e) => e.value == value).key;

  String get wire => _wire[this]!;

  String get label => switch (this) {
        HoldRole.start => 'Salida',
        HoldRole.hand => 'Mano',
        HoldRole.footOnly => 'Sólo pie',
        HoldRole.top => 'Top',
      };
}

/// `route_status_enum`.
enum RouteStatus {
  draft,
  active,
  archivedDismantled;

  static const _wire = {
    RouteStatus.draft: 'draft',
    RouteStatus.active: 'active',
    RouteStatus.archivedDismantled: 'archived_dismantled',
  };

  static RouteStatus fromWire(String value) =>
      _wire.entries.firstWhere((e) => e.value == value).key;

  String get wire => _wire[this]!;

  String get label => switch (this) {
        RouteStatus.draft => 'Borrador',
        RouteStatus.active => 'Montado',
        RouteStatus.archivedDismantled => 'Desmontado',
      };
}

/// `user_role_enum`.
enum UserRole {
  climber,
  routeSetter,
  admin;

  static const _wire = {
    UserRole.climber: 'climber',
    UserRole.routeSetter: 'route_setter',
    UserRole.admin: 'admin',
  };

  static UserRole fromWire(String value) =>
      _wire.entries.firstWhere((e) => e.value == value).key;

  String get wire => _wire[this]!;
}

/// `membership_status_enum`.
enum MembershipStatus {
  pending,
  authorized,
  revoked;

  static MembershipStatus fromWire(String value) =>
      MembershipStatus.values.firstWhere((e) => e.name == value);

  String get wire => name;

  String get label => switch (this) {
        MembershipStatus.pending => 'Pendiente',
        MembershipStatus.authorized => 'Autorizado',
        MembershipStatus.revoked => 'Revocado',
      };
}

/// Scopes de `POST /uploads/presign` — 04 §2.10.
enum UploadScope {
  holdCrop,
  wallPhoto,
  gymLogo,
  userAvatar;

  static const _wire = {
    UploadScope.holdCrop: 'hold_crop',
    UploadScope.wallPhoto: 'wall_photo',
    UploadScope.gymLogo: 'gym_logo',
    UploadScope.userAvatar: 'user_avatar',
  };

  String get wire => _wire[this]!;
}
