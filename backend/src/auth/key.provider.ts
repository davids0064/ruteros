import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';

/**
 * Par de claves RS256 (RNF-4). Tres orígenes, en este orden:
 *
 * 1. `JWT_PRIVATE_KEY` / `JWT_PUBLIC_KEY` — el PEM completo en la variable.
 *    Es la vía en Railway y en cualquier plataforma sin disco persistente.
 * 2. `JWT_PRIVATE_KEY_PATH` / `JWT_PUBLIC_KEY_PATH` — ficheros en disco (local).
 * 3. Par efímero en memoria, sólo para pruebas y arranque en frío.
 *
 * El par efímero invalida todas las sesiones en cada reinicio, así que fuera de
 * desarrollo se exige uno de los dos primeros: en producción es un fallo de
 * arranque, no un warning que nadie lee.
 */
@Injectable()
export class KeyProvider {
  private readonly logger = new Logger(KeyProvider.name);
  readonly privateKey: string;
  readonly publicKey: string;

  constructor(config: ConfigService) {
    const inlinePrivate = normalizePem(config.get<string>('JWT_PRIVATE_KEY'));
    const inlinePublic = normalizePem(config.get<string>('JWT_PUBLIC_KEY'));

    if (inlinePrivate && inlinePublic) {
      this.privateKey = inlinePrivate;
      this.publicKey = inlinePublic;
      return;
    }

    const privPath = config.get<string>('JWT_PRIVATE_KEY_PATH');
    const pubPath = config.get<string>('JWT_PUBLIC_KEY_PATH');

    if (privPath && pubPath) {
      this.privateKey = readFileSync(privPath, 'utf8');
      this.publicKey = readFileSync(pubPath, 'utf8');
      return;
    }

    if (config.get<string>('NODE_ENV') === 'production') {
      throw new Error(
        'Faltan las claves RS256: define JWT_PRIVATE_KEY/JWT_PUBLIC_KEY (PEM en la ' +
          'variable) o JWT_PRIVATE_KEY_PATH/JWT_PUBLIC_KEY_PATH. Con un par efímero, ' +
          'cada despliegue cerraría la sesión de todos los usuarios.',
      );
    }

    this.logger.warn(
      'JWT_PRIVATE_KEY(_PATH)/JWT_PUBLIC_KEY(_PATH) no configurados: se genera un par RS256 efímero.',
    );
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
      privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
      publicKeyEncoding: { type: 'spki', format: 'pem' },
    });
    this.privateKey = privateKey;
    this.publicKey = publicKey;
  }
}

/**
 * Acepta el PEM tal cual (multilínea), con `\n` escapados —como lo deja pegar
 * la UI de Railway— o en base64, que es lo que sobrevive a cualquier shell.
 */
function normalizePem(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  const value = raw.trim();
  if (!value) return undefined;
  if (value.includes('-----BEGIN')) return value.replace(/\\n/g, '\n');
  return Buffer.from(value, 'base64').toString('utf8');
}
