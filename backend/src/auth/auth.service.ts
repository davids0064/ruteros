import { Inject, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import * as bcrypt from 'bcryptjs';
import { KYSELY, type Db } from '../database/database.module';
import { DomainException, notFound } from '../common/errors/domain.exception';
import { KeyProvider } from './key.provider';
import type {
  AuthSessionDTO,
  GymMembershipDTO,
  LoginPayload,
  RegisterPayload,
  UpdateProfilePayload,
  UserProfileDTO,
} from './dto/auth.dto';
import type { JwtMembershipClaim, RefreshPayload } from './jwt-payload';

@Injectable()
export class AuthService {
  private readonly accessTtl: number;
  private readonly refreshTtl: number;
  private readonly issuer: string;

  constructor(
    @Inject(KYSELY) private readonly db: Db,
    private readonly jwt: JwtService,
    private readonly keys: KeyProvider,
    config: ConfigService,
  ) {
    this.accessTtl = Number(config.get('JWT_ACCESS_TTL') ?? 900);
    this.refreshTtl = Number(config.get('JWT_REFRESH_TTL') ?? 2592000);
    this.issuer = config.get<string>('JWT_ISSUER') ?? 'boulder-cosetter';
  }

  async register(payload: RegisterPayload): Promise<AuthSessionDTO> {
    const passwordHash = await bcrypt.hash(payload.password, 12);

    // La unicidad de email/username la impone PostgreSQL; el 23505 lo traduce
    // AllExceptionsFilter a EMAIL_ALREADY_REGISTERED (04 §2.2).
    const user = await this.db
      .insertInto('users')
      .values({
        email: payload.email.toLowerCase(),
        password_hash: passwordHash,
        username: payload.username,
        display_name: payload.displayName ?? null,
        role: 'climber', // 04 §2.3: `role` por defecto 'climber'
      })
      .returning('id')
      .executeTakeFirstOrThrow();

    return this.issueSession(user.id);
  }

  async login(payload: LoginPayload): Promise<AuthSessionDTO> {
    const row = await this.db
      .selectFrom('users')
      .select(['id', 'password_hash', 'is_active'])
      .where('email', '=', payload.email.toLowerCase())
      .executeTakeFirst();

    const invalid = new DomainException('UNAUTHENTICATED', 'Credenciales inválidas.');
    if (!row?.password_hash || !row.is_active) throw invalid;
    if (!(await bcrypt.compare(payload.password, row.password_hash))) throw invalid;

    return this.issueSession(row.id);
  }

  /**
   * Rotación de refresh token (04 §2.3) — de un solo uso.
   *
   * Cada canje incrementa `users.token_version`, de modo que el token entregado
   * queda muerto en el acto: sin ese incremento los claims (`sub`, `tv`, `typ`)
   * serían idénticos entre canjes y el token «rotado» seguiría siendo el mismo
   * secreto, válido durante 30 días. El efecto secundario es deseado: reusar un
   * refresh token robado falla, y el titular legítimo lo nota al instante.
   */
  async refresh(refreshToken: string): Promise<AuthSessionDTO> {
    let claims: RefreshPayload;
    try {
      claims = await this.jwt.verifyAsync<RefreshPayload>(refreshToken, {
        publicKey: this.keys.publicKey,
        algorithms: ['RS256'],
        issuer: this.issuer,
      });
    } catch {
      throw new DomainException('UNAUTHENTICATED', 'Refresh token inválido o expirado.');
    }
    if (claims.typ !== 'refresh') {
      throw new DomainException('UNAUTHENTICATED', 'El token entregado no es de refresco.');
    }

    // El canje es atómico: el UPDATE sólo prospera si `tv` sigue alineado, así
    // que dos canjes simultáneos del mismo token dejan vivo exactamente a uno.
    const rotated = await this.db
      .updateTable('users')
      .set((eb) => ({ token_version: eb('token_version', '+', 1) }))
      .where('id', '=', claims.sub)
      .where('token_version', '=', claims.tv)
      .where('is_active', '=', true)
      .returning('id')
      .executeTakeFirst();

    // `tv` desalineado => el token ya se canjeó, o una membresía se recortó
    // (trigger de la migración 008): sesión muerta.
    if (!rotated) {
      throw new DomainException(
        'UNAUTHENTICATED',
        'La sesión ha sido invalidada. Inicia sesión de nuevo.',
      );
    }

    return this.issueSession(rotated.id);
  }

  async getProfile(userId: string): Promise<UserProfileDTO> {
    const user = await this.db
      .selectFrom('users')
      .select(['id', 'email', 'username', 'display_name', 'avatar_url', 'role'])
      .where('id', '=', userId)
      .executeTakeFirst();
    if (!user) throw notFound('El usuario');

    return {
      id: user.id,
      email: user.email,
      username: user.username,
      ...(user.display_name ? { displayName: user.display_name } : {}),
      ...(user.avatar_url ? { avatarUrl: user.avatar_url } : {}),
      role: user.role,
      memberships: await this.listMemberships(userId),
    };
  }

  async updateProfile(userId: string, payload: UpdateProfilePayload): Promise<UserProfileDTO> {
    const patch = {
      ...(payload.username !== undefined ? { username: payload.username } : {}),
      ...(payload.displayName !== undefined ? { display_name: payload.displayName } : {}),
      ...(payload.avatarUrl !== undefined ? { avatar_url: payload.avatarUrl } : {}),
    };

    if (Object.keys(patch).length > 0) {
      await this.db
        .updateTable('users')
        .set({ ...patch, updated_at: new Date() })
        .where('id', '=', userId)
        .execute();
    }
    return this.getProfile(userId);
  }

  /** Todas las membresías del usuario — alimenta el KPI multi-boulder. */
  private async listMemberships(userId: string): Promise<GymMembershipDTO[]> {
    const rows = await this.db
      .selectFrom('gym_setters as gs')
      .innerJoin('boulder_gyms as g', 'g.id', 'gs.gym_id')
      .select(['gs.gym_id', 'g.name as gym_name', 'gs.status', 'gs.is_gym_admin'])
      .where('gs.user_id', '=', userId)
      .orderBy('g.name')
      .execute();

    return rows.map((r) => ({
      gymId: r.gym_id,
      gymName: r.gym_name,
      status: r.status,
      isGymAdmin: r.is_gym_admin,
    }));
  }

  /** Emite el par access/refresh y adjunta el perfil (04 §2.3). */
  async issueSession(userId: string): Promise<AuthSessionDTO> {
    const user = await this.db
      .selectFrom('users')
      .select(['id', 'email', 'role', 'token_version'])
      .where('id', '=', userId)
      .executeTakeFirstOrThrow();

    const profile = await this.getProfile(userId);

    // §4.1: sólo las membresías 'authorized' viajan en el access token.
    const claims: JwtMembershipClaim[] = profile.memberships
      .filter((m) => m.status === 'authorized')
      .map((m) => ({ gymId: m.gymId, isGymAdmin: m.isGymAdmin }));

    const signOptions = {
      privateKey: this.keys.privateKey,
      algorithm: 'RS256' as const,
      issuer: this.issuer,
    };

    const accessToken = await this.jwt.signAsync(
      { sub: user.id, email: user.email, role: user.role, memberships: claims },
      { ...signOptions, expiresIn: this.accessTtl },
    );
    const refreshToken = await this.jwt.signAsync(
      { sub: user.id, tv: user.token_version, typ: 'refresh' },
      { ...signOptions, expiresIn: this.refreshTtl },
    );

    return { accessToken, refreshToken, expiresIn: this.accessTtl, user: profile };
  }
}
