#!/usr/bin/env node
/** Genera el par RS256 en ./keys (RNF-4). */
const { generateKeyPairSync } = require('node:crypto');
const { mkdirSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');

const dir = join(__dirname, '..', 'keys');
mkdirSync(dir, { recursive: true });

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
  publicKeyEncoding: { type: 'spki', format: 'pem' },
});

writeFileSync(join(dir, 'jwt-private.pem'), privateKey, { mode: 0o600 });
writeFileSync(join(dir, 'jwt-public.pem'), publicKey);
console.log('Claves RS256 escritas en backend/keys/ (no versionar)');
