/** Forma única de toda respuesta >= 400 — 04 §2.2. */
export interface ApiErrorResponse {
  statusCode: number;
  errorCode: string;
  message: string;
  details?: unknown;
  timestamp: string;
  path: string;
}

/** Envoltorio de paginación — 04 §2.1. */
export interface PaginatedResponse<T> {
  data: T[];
  meta: { page: number; pageSize: number; total: number };
}
