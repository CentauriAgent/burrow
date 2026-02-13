/**
 * Nostr identity management for Burrow.
 * Reads/generates Nostr keypairs, derives MLS credentials.
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
import { schnorr, secp256k1 } from '@noble/curves/secp256k1.js';
import { randomBytes } from 'node:crypto';

export interface NostrIdentity {
  secretKey: Uint8Array; // 32 bytes raw secret key
  publicKey: Uint8Array; // 32 bytes x-only pubkey (schnorr)
  publicKeyHex: string;
  secretKeyHex: string;
}

const DEFAULT_KEY_PATH = `${process.env.HOME}/.clawstr/secret.key`;

/**
 * Load Nostr identity from secret key file.
 * The file contains nsec or hex-encoded 32-byte secret key.
 */
export function loadIdentity(keyPath?: string): NostrIdentity {
  const path = keyPath || DEFAULT_KEY_PATH;

  if (!existsSync(path)) {
    throw new Error(
      `Secret key not found at ${path}. Run 'burrow init' to generate one.`
    );
  }

  const raw = readFileSync(path, 'utf-8').trim();
  let secretKey: Uint8Array;

  if (raw.startsWith('nsec1')) {
    // Bech32-encoded nsec - decode it
    // nostr-tools nip19 decode
    const { nip19 } = require('nostr-tools');
    const decoded = nip19.decode(raw);
    if (decoded.type !== 'nsec') throw new Error('Invalid nsec key');
    secretKey = decoded.data as Uint8Array;
  } else {
    // Hex-encoded
    secretKey = hexToBytes(raw);
  }

  if (secretKey.length !== 32) {
    throw new Error(`Invalid secret key length: ${secretKey.length} (expected 32)`);
  }

  const publicKey = schnorr.getPublicKey(secretKey);
  return {
    secretKey,
    publicKey,
    publicKeyHex: bytesToHex(publicKey),
    secretKeyHex: bytesToHex(secretKey),
  };
}

/**
 * Generate a new Nostr identity and save it.
 */
export function generateIdentity(keyPath?: string): NostrIdentity {
  const path = keyPath || DEFAULT_KEY_PATH;
  const secretKey = randomBytes(32);
  const publicKey = schnorr.getPublicKey(new Uint8Array(secretKey));

  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytesToHex(new Uint8Array(secretKey)), { mode: 0o600 });

  return {
    secretKey: new Uint8Array(secretKey),
    publicKey,
    publicKeyHex: bytesToHex(publicKey),
    secretKeyHex: bytesToHex(new Uint8Array(secretKey)),
  };
}

/**
 * Get raw 32-byte identity bytes for MLS BasicCredential.
 * MIP-00 requires raw 32-byte public key (not hex).
 */
export function getCredentialIdentity(identity: NostrIdentity): Uint8Array {
  return identity.publicKey;
}
