import { HttpException } from '@nestjs/common';
import { ERROR_CODES, type ErrorCode } from './error-codes';

/**
 * Excepción de dominio. El `errorCode` viaja al cliente tal cual; el status
 * HTTP lo determina la tabla de §2.2, nunca el llamador.
 */
export class DomainException extends HttpException {
  readonly errorCode: ErrorCode;
  readonly details?: unknown;

  constructor(errorCode: ErrorCode, message: string, details?: unknown) {
    const { status } = ERROR_CODES[errorCode];
    super({ errorCode, message, details }, status);
    this.errorCode = errorCode;
    this.details = details;
  }
}

export const notFound = (what: string) =>
  new DomainException('RESOURCE_NOT_FOUND', `${what} no existe o está fuera de tu alcance.`);
