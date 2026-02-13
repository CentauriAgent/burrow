/**
 * Nostr identity management for Burrow.
 * Reads/generates Nostr keypairs, derives MLS credentials.
 */
export interface NostrIdentity {
    secretKey: Uint8Array;
    publicKey: Uint8Array;
    publicKeyHex: string;
    secretKeyHex: string;
}
/**
 * Load Nostr identity from secret key file.
 * The file contains nsec or hex-encoded 32-byte secret key.
 */
export declare function loadIdentity(keyPath?: string): NostrIdentity;
/**
 * Generate a new Nostr identity and save it.
 */
export declare function generateIdentity(keyPath?: string): NostrIdentity;
/**
 * Get raw 32-byte identity bytes for MLS BasicCredential.
 * MIP-00 requires raw 32-byte public key (not hex).
 */
export declare function getCredentialIdentity(identity: NostrIdentity): Uint8Array;
//# sourceMappingURL=identity.d.ts.map