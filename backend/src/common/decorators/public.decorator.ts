import { SetMetadata } from '@nestjs/common';

export const IS_PUBLIC_KEY = 'isPublic';
/** Exime del JwtAuthGuard global: /auth/register, /auth/login, /auth/refresh (04 §2.1). */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

export const IS_OPTIONAL_AUTH_KEY = 'isOptionalAuth';
/** Endpoint público que, si llega un JWT válido, lo usa para ampliar el alcance. */
export const OptionalAuth = () => SetMetadata(IS_OPTIONAL_AUTH_KEY, true);
