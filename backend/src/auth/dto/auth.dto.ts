import {
  IsEmail,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
  IsUrl,
} from 'class-validator';

/** 04 §2.3 */
export class RegisterPayload {
  @IsEmail({}, { message: 'El correo no tiene un formato válido.' })
  @MaxLength(255)
  email!: string;

  @IsString()
  @MinLength(10, { message: 'La contraseña debe tener al menos 10 caracteres.' })
  @MaxLength(200)
  password!: string;

  @Matches(/^[a-z0-9_]{3,60}$/, {
    message: 'El usuario admite sólo minúsculas, dígitos y guion bajo (3-60).',
  })
  username!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  displayName?: string;
}

export class LoginPayload {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(1)
  password!: string;
}

export class RefreshPayloadDto {
  @IsString()
  @MinLength(1)
  refreshToken!: string;
}

export class UpdateProfilePayload {
  @IsOptional()
  @Matches(/^[a-z0-9_]{3,60}$/)
  username?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  displayName?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  avatarUrl?: string;
}

export interface GymMembershipDTO {
  gymId: string;
  gymName: string;
  status: 'pending' | 'authorized' | 'revoked';
  isGymAdmin: boolean;
}

export interface UserProfileDTO {
  id: string;
  email: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
  role: 'climber' | 'route_setter' | 'admin';
  memberships: GymMembershipDTO[];
}

export interface AuthSessionDTO {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
  user: UserProfileDTO;
}
