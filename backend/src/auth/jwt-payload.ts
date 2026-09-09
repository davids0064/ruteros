/** 04_COMPONENT_SPECS.md §4.1 */
export interface JwtMembershipClaim {
  gymId: string;
  isGymAdmin: boolean;
}

export interface JwtPayload {
  sub: string; // users.id — única fuente de autoría (RF-4.3)
  email: string;
  role: 'climber' | 'route_setter' | 'admin';
  /** Sólo membresías con status = 'authorized'. Se embeben para evitar un
   *  SELECT por petición (RNF-3); revocar surte efecto al renovar (<= 900 s). */
  memberships: JwtMembershipClaim[];
  iat: number;
  exp: number;
}

/** Claims del refresh token. `tv` = users.token_version (migración 008). */
export interface RefreshPayload {
  sub: string;
  tv: number;
  typ: 'refresh';
  iat: number;
  exp: number;
}

export interface AuthenticatedUser {
  id: string;
  email: string;
  role: JwtPayload['role'];
  memberships: JwtMembershipClaim[];
}

export const isMemberOf = (user: AuthenticatedUser, gymId: string): boolean =>
  user.memberships.some((m) => m.gymId === gymId);

export const isAdminOf = (user: AuthenticatedUser, gymId: string): boolean =>
  user.memberships.some((m) => m.gymId === gymId && m.isGymAdmin);
