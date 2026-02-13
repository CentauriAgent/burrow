/**
 * MLS KeyPackage generation and management per MIP-00.
 * Uses ts-mls for real MLS operations.
 */
import { type KeyPackage, type PrivateKeyPackage, type CiphersuiteName } from 'ts-mls';
import type { NostrIdentity } from '../crypto/identity.js';
export interface GeneratedKeyPackage {
    keyPackage: KeyPackage;
    privateKeyPackage: PrivateKeyPackage;
    serialized: Uint8Array;
    serializedBase64: string;
}
/**
 * Generate a new MLS KeyPackage per MIP-00 requirements.
 */
export declare function generateMarmotKeyPackage(identity: NostrIdentity, ciphersuiteName?: CiphersuiteName, isLastResort?: boolean): Promise<GeneratedKeyPackage>;
/**
 * Get the ciphersuite hex ID string for tags (e.g., "0x0001").
 */
export declare function getCiphersuiteHexId(name: CiphersuiteName): string;
//# sourceMappingURL=keypackage.d.ts.map