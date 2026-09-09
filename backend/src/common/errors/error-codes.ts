/**
 * Catálogo único de errores — 04_COMPONENT_SPECS.md §2.2.
 * Cada constante es estable y forma parte del contrato público de la API.
 */
export const ERROR_CODES = {
  VALIDATION_FAILED: { code: 'VALIDATION_FAILED', status: 400 },
  UNAUTHENTICATED: { code: 'UNAUTHENTICATED', status: 401 },
  NOT_GYM_MEMBER: { code: 'NOT_GYM_MEMBER', status: 403 },
  NOT_GYM_ADMIN: { code: 'NOT_GYM_ADMIN', status: 403 },
  NOT_ROUTE_AUTHOR: { code: 'NOT_ROUTE_AUTHOR', status: 403 },
  RESOURCE_NOT_FOUND: { code: 'RESOURCE_NOT_FOUND', status: 404 },
  HOLD_NOT_AVAILABLE: { code: 'HOLD_NOT_AVAILABLE', status: 409 },
  DUPLICATE_HOLD_IN_ROUTE: { code: 'DUPLICATE_HOLD_IN_ROUTE', status: 409 },
  ROUTE_ALREADY_DISMANTLED: { code: 'ROUTE_ALREADY_DISMANTLED', status: 409 },
  AUTHOR_HAS_ROUTES: { code: 'AUTHOR_HAS_ROUTES', status: 409 },
  EMAIL_ALREADY_REGISTERED: { code: 'EMAIL_ALREADY_REGISTERED', status: 409 },
  GRADE_SYSTEM_MISMATCH: { code: 'GRADE_SYSTEM_MISMATCH', status: 422 },
  INTERNAL_ERROR: { code: 'INTERNAL_ERROR', status: 500 },
} as const;

export type ErrorCode = keyof typeof ERROR_CODES;
