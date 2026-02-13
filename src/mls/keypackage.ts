/**
 * MLS KeyPackage generation and management per MIP-00.
 * Uses ts-mls for real MLS operations.
 */

import {
  generateKeyPackage,
  getCiphersuiteFromName,
  getCiphersuiteImpl,
  defaultCapabilities,
  defaultLifetime,
  encodeMlsMessage,
  bytesToBase64,
  type KeyPackage,
  type PrivateKeyPackage,
  type CiphersuiteName,
  type Extension,
  type Capabilities,
} from 'ts-mls';
import { MARMOT_EXTENSION_ID, LAST_RESORT_EXTENSION_ID } from '../types/index.js';
import type { NostrIdentity } from '../crypto/identity.js';
import { getCredentialIdentity } from '../crypto/identity.js';

export interface GeneratedKeyPackage {
  keyPackage: KeyPackage;
  privateKeyPackage: PrivateKeyPackage;
  serialized: Uint8Array;
  serializedBase64: string;
}

/**
 * Generate a new MLS KeyPackage per MIP-00 requirements.
 */
export async function generateMarmotKeyPackage(
  identity: NostrIdentity,
  ciphersuiteName: CiphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
  isLastResort = true,
): Promise<GeneratedKeyPackage> {
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);

  const credentialIdentity = getCredentialIdentity(identity);

  const credential = {
    credentialType: 'basic' as const,
    identity: credentialIdentity,
  };

  // defaultCapabilities is a function
  const caps: Capabilities = {
    ...defaultCapabilities(),
    extensions: [
      ...(defaultCapabilities().extensions || []),
      MARMOT_EXTENSION_ID,
      LAST_RESORT_EXTENSION_ID,
    ],
  };

  const lifetime = defaultLifetime;

  const extensions: Extension[] = isLastResort
    ? [{ extensionType: LAST_RESORT_EXTENSION_ID, extensionData: new Uint8Array(0) }]
    : [];

  // generateKeyPackage(credential, capabilities, lifetime, extensions, cs, leafNodeExtensions?)
  const result = await generateKeyPackage(credential, caps, lifetime, extensions, cs);

  // result has { publicPackage, privatePackage }
  const serialized = encodeMlsMessage({
    wireformat: 'mls_key_package' as any,
    keyPackage: result.publicPackage,
  } as any);

  return {
    keyPackage: result.publicPackage,
    privateKeyPackage: result.privatePackage,
    serialized,
    serializedBase64: bytesToBase64(serialized),
  };
}

/**
 * Get the ciphersuite hex ID string for tags (e.g., "0x0001").
 */
export function getCiphersuiteHexId(name: CiphersuiteName): string {
  // Map known ciphersuite names to IDs
  const map: Record<string, number> = {
    'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519': 0x0001,
    'MLS_128_DHKEMP256_AES128GCM_SHA256_P256': 0x0002,
    'MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519': 0x0003,
  };
  const id = map[name] || 0x0001;
  return `0x${id.toString(16).padStart(4, '0')}`;
}
