/**
 * NIP-44 encryption for Marmot group messages.
 *
 * Per MIP-03: Group message encryption uses the MLS exporter_secret as both
 * the sender private key and derives the receiver public key from it,
 * then applies standard NIP-44.
 */
/**
 * Encrypt content for a group message using exporter_secret per MIP-03.
 *
 * 1. Use exporter_secret as private key
 * 2. Derive corresponding public key
 * 3. Use NIP-44 with that keypair (self-encryption effectively)
 */
export declare function encryptGroupMessage(content: Uint8Array, exporterSecret: Uint8Array): string;
/**
 * Decrypt group message content using exporter_secret per MIP-03.
 */
export declare function decryptGroupMessage(encryptedContent: string, exporterSecret: Uint8Array): Uint8Array;
/**
 * Encrypt a Welcome event for a specific recipient using NIP-59 gift-wrapping.
 * Per MIP-02: Welcome events use NIP-59 for privacy.
 */
export declare function encryptForRecipient(content: string, senderSecret: Uint8Array, recipientPubkey: string): string;
/**
 * Decrypt content from a sender.
 */
export declare function decryptFromSender(encrypted: string, recipientSecret: Uint8Array, senderPubkey: string): string;
//# sourceMappingURL=nip44.d.ts.map