import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { DomainException } from '../errors/domain.exception';
import { ERROR_CODES, type ErrorCode } from '../errors/error-codes';
import type { ApiErrorResponse } from '../dto/api-error.dto';

/**
 * Traduce TODA excepción a `ApiErrorResponse` (04 §2.2).
 *
 * Incluye el puente SQLSTATE -> errorCode: las invariantes que viven en
 * PostgreSQL (triggers de 006/007, UNIQUE, FK RESTRICT) afloran como códigos
 * de contrato sin que la capa de negocio las duplique (regla de oro, §0.1).
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<Response>();
    const req = ctx.getRequest<Request>();

    const { errorCode, status, message, details } = this.classify(exception);

    if (status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(`${req.method} ${req.url} -> ${errorCode}`, exception as Error);
    }

    const body: ApiErrorResponse = {
      statusCode: status,
      errorCode,
      message,
      ...(details !== undefined ? { details } : {}),
      timestamp: new Date().toISOString(),
      path: req.url,
    };
    res.status(status).json(body);
  }

  private classify(exception: unknown): {
    errorCode: ErrorCode;
    status: number;
    message: string;
    details?: unknown;
  } {
    if (exception instanceof DomainException) {
      return {
        errorCode: exception.errorCode,
        status: exception.getStatus(),
        message: (exception.getResponse() as { message: string }).message,
        details: exception.details,
      };
    }

    const fromPg = this.fromPostgres(exception);
    if (fromPg) return fromPg;

    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const payload = exception.getResponse();
      const message =
        typeof payload === 'string'
          ? payload
          : ((payload as { message?: string | string[] }).message ?? exception.message);
      const details =
        typeof payload === 'object' && Array.isArray((payload as { message?: unknown }).message)
          ? (payload as { message: string[] }).message
          : undefined;

      const errorCode: ErrorCode =
        status === 400
          ? 'VALIDATION_FAILED'
          : status === 401
            ? 'UNAUTHENTICATED'
            : status === 404
              ? 'RESOURCE_NOT_FOUND'
              : status === 403
                ? 'NOT_GYM_MEMBER'
                : 'INTERNAL_ERROR';

      return {
        errorCode,
        status,
        message: Array.isArray(message) ? 'La petición no supera la validación.' : message,
        details,
      };
    }

    return {
      errorCode: 'INTERNAL_ERROR',
      status: ERROR_CODES.INTERNAL_ERROR.status,
      message: 'Error interno del servidor.',
    };
  }

  /** Puente SQLSTATE -> contrato REST. */
  private fromPostgres(
    exception: unknown,
  ): { errorCode: ErrorCode; status: number; message: string } | null {
    const e = exception as { code?: string; constraint?: string; detail?: string };
    if (!e?.code) return null;

    const build = (errorCode: ErrorCode, message: string) => ({
      errorCode,
      status: ERROR_CODES[errorCode].status,
      message,
    });

    switch (e.code) {
      // 55006 object_in_use — lo lanza mark_hold_as_in_use (migración 007)
      case '55006':
        return build('HOLD_NOT_AVAILABLE', 'Alguna presa del bloque ya no está disponible.');

      case '23505': // unique_violation
        if (e.constraint === 'unique_hold_per_active_route') {
          return build('DUPLICATE_HOLD_IN_ROUTE', 'La misma presa aparece dos veces en el bloque.');
        }
        if (e.constraint?.includes('users_email')) {
          return build('EMAIL_ALREADY_REGISTERED', 'Ese correo ya está registrado.');
        }
        return build('VALIDATION_FAILED', 'Ya existe un registro con esos valores únicos.');

      case '23503': // foreign_key_violation
        if (e.constraint?.includes('creator_id')) {
          return build('AUTHOR_HAS_ROUTES', 'El usuario tiene rutas firmadas y no puede borrarse.');
        }
        return build('VALIDATION_FAILED', 'Referencia inexistente en la petición.');

      case '23514': // check_violation
        return build('VALIDATION_FAILED', 'La petición viola una restricción del dominio.');

      default:
        return null;
    }
  }
}
