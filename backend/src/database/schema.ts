/**
 * Tipado Kysely del esquema físico.
 *
 * Fuente de verdad: `db/migrations/*.sql` (a su vez transcripción de
 * `.specs/03_DATA_MODELS.md`). Kysely CONSUME el esquema; no lo posee
 * (04_COMPONENT_SPECS.md §0.1). Los nombres de columna son snake_case
 * literal y NUNCA se alteran — la traducción a camelCase ocurre en la capa
 * de mapeo (§3).
 */
import type { ColumnType, Generated, JSONColumnType } from 'kysely';

// --- ENUMs canónicos (001_extensions_and_enums.sql) --------------------------
export type HoldStatusEnum = 'available' | 'in_use' | 'maintenance' | 'retired';
export type HoldTypeEnum = 'crimp' | 'sloper' | 'jug' | 'pinch' | 'foothold' | 'volume';
export type RouteStatusEnum = 'draft' | 'active' | 'archived_dismantled';
export type HoldRoleEnum = 'start' | 'hand' | 'foot_only' | 'top';
export type UserRoleEnum = 'climber' | 'route_setter' | 'admin';
export type MembershipStatusEnum = 'pending' | 'authorized' | 'revoked';

/** TIMESTAMPTZ con DEFAULT: opcional al insertar, escribible al actualizar. */
type Timestamp = ColumnType<Date, Date | string | undefined, Date | string>;

export interface UsersTable {
  id: Generated<string>;
  email: string;
  password_hash: string | null;
  auth_provider: Generated<string>;
  provider_subject_id: string | null;
  username: string;
  display_name: string | null;
  avatar_url: string | null;
  role: Generated<UserRoleEnum>;
  is_active: Generated<boolean>;
  /** Invalidación de refresh tokens (migración 008, 04 §4.1). */
  token_version: Generated<number>;
  created_at: Timestamp;
  updated_at: Timestamp;
}

export interface BoulderGymsTable {
  id: Generated<string>;
  name: string;
  address: string;
  city: string;
  country: string;
  phone: string | null;
  email: string | null;
  pricing_plans: Generated<JSONColumnType<Record<string, unknown>>>;
  logo_url: string | null;
  created_at: Timestamp;
  updated_at: Timestamp;
}

export interface GymSettersTable {
  id: Generated<string>;
  gym_id: string;
  user_id: string;
  status: Generated<MembershipStatusEnum>;
  is_gym_admin: Generated<boolean>;
  authorized_by: string | null;
  authorized_at: Timestamp | null;
  created_at: Timestamp;
}

export interface GradeSystemsTable {
  id: Generated<string>;
  gym_id: string | null; // NULL => sistema global
  name: string;
  description: string | null;
  is_active: Generated<boolean>;
  created_at: Timestamp;
}

export interface GradeValuesTable {
  id: Generated<string>;
  system_id: string;
  level_label: string;
  rank_ordinal: number;
  weight_factor: Generated<number>;
  created_at: Timestamp;
}

export interface WallsTable {
  id: Generated<string>;
  gym_id: string;
  creator_id: string | null;
  name: string;
  photo_url: string;
  width_cm: number;
  height_cm: number;
  default_incline_deg: Generated<number>;
  default_grade_system_id: string | null;
  is_public: Generated<boolean>;
  created_at: Timestamp;
  updated_at: Timestamp;
}

export interface HoldSetsTable {
  id: Generated<string>;
  gym_id: string;
  creator_id: string | null;
  name: string;
  color_hex: string;
  created_at: Timestamp;
}

export interface HoldsTable {
  id: Generated<string>;
  set_id: string;
  image_crop_url: string;
  type_category: Generated<HoldTypeEnum>;
  /** Escrito EXCLUSIVAMENTE por los triggers en la transición available <-> in_use. */
  status: Generated<HoldStatusEnum>;
  difficulty_rating_weight: Generated<number>;
  bounding_box_data: JSONColumnType<{ width_px: number; height_px: number }> | null;
  created_at: Timestamp;
}

export interface RoutesTable {
  id: Generated<string>;
  wall_id: string;
  /** Autoría inmutable: se escribe una sola vez desde JWT.sub (04 §4.2). */
  creator_id: string;
  title: string;
  target_grade_id: string;
  calculated_grade_id: string | null;
  wall_incline_deg: number;
  status: Generated<RouteStatusEnum>;
  created_at: Timestamp;
  /** Sellado por trigger_release_holds_dismantle. El servicio NO lo escribe. */
  dismantled_at: Timestamp | null;
}

export interface PlacedHoldsTable {
  id: Generated<string>;
  route_id: string;
  hold_id: string;
  x_percent: number;
  y_percent: number;
  rotation_deg: Generated<number>;
  hold_role: Generated<HoldRoleEnum>;
}

export interface Database {
  users: UsersTable;
  boulder_gyms: BoulderGymsTable;
  gym_setters: GymSettersTable;
  grade_systems: GradeSystemsTable;
  grade_values: GradeValuesTable;
  walls: WallsTable;
  hold_sets: HoldSetsTable;
  holds: HoldsTable;
  routes: RoutesTable;
  placed_holds: PlacedHoldsTable;
}
