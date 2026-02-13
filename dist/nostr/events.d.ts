/**
 * Nostr event builders for Marmot protocol event kinds.
 */
import type { NostrIdentity } from '../crypto/identity.js';
import type { CiphersuiteName } from 'ts-mls';
/**
 * Build a kind 443 KeyPackage event per MIP-00.
 */
export declare function buildKeyPackageEvent(identity: NostrIdentity, keyPackageBase64: string, opts: {
    ciphersuiteName?: CiphersuiteName;
    relays: string[];
    client?: string;
}): any;
/**
 * Build a kind 445 Group Event (encrypted MLS message) per MIP-03.
 * Uses an ephemeral keypair for publishing.
 */
export declare function buildGroupEvent(nostrGroupIdHex: string, encryptedContent: string): {
    event: any;
    ephemeralSecret: Uint8Array;
};
/**
 * Build an unsigned inner application message (kind 9 chat) per MIP-03.
 * Inner events MUST be unsigned and MUST NOT include h tags.
 */
export declare function buildInnerChatMessage(senderPubkeyHex: string, text: string, replyToId?: string): any;
/**
 * Build a kind 444 Welcome event (unsigned) per MIP-02.
 * This is wrapped in NIP-59 gift-wrapping before sending.
 */
export declare function buildWelcomeEvent(welcomeBase64: string, keyPackageEventId: string, relays: string[]): any;
//# sourceMappingURL=events.d.ts.map