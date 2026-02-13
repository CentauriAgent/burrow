/**
 * NIP-44 encryption for Marmot group messages.
 *
 * Per MIP-03: Group message encryption uses the MLS exporter_secret as both
 * the sender private key and derives the receiver public key from it,
 * then applies standard NIP-44.
 */
import { nip44 } from 'nostr-tools';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
/**
 * Encrypt content for a group message using exporter_secret per MIP-03.
 *
 * 1. Use exporter_secret as private key
 * 2. Derive corresponding public key
 * 3. Use NIP-44 with that keypair (self-encryption effectively)
 */
export function encryptGroupMessage(content, exporterSecret) {
    const secretHex = bytesToHex(exporterSecret);
    const pubkey = secp256k1.getPublicKey(exporterSecret, true).slice(1); // x-only 32 bytes
    // NIP-44 conversation key from secret + pubkey
    const conversationKey = nip44.v2.utils.getConversationKey(hexToBytes(secretHex), bytesToHex(pubkey));
    return nip44.v2.encrypt(new TextDecoder().decode(content), conversationKey);
}
/**
 * Decrypt group message content using exporter_secret per MIP-03.
 */
export function decryptGroupMessage(encryptedContent, exporterSecret) {
    const secretHex = bytesToHex(exporterSecret);
    const pubkey = secp256k1.getPublicKey(exporterSecret, true).slice(1);
    const conversationKey = nip44.v2.utils.getConversationKey(hexToBytes(secretHex), bytesToHex(pubkey));
    const decrypted = nip44.v2.decrypt(encryptedContent, conversationKey);
    return new TextEncoder().encode(decrypted);
}
/**
 * Encrypt a Welcome event for a specific recipient using NIP-59 gift-wrapping.
 * Per MIP-02: Welcome events use NIP-59 for privacy.
 */
export function encryptForRecipient(content, senderSecret, recipientPubkey) {
    const conversationKey = nip44.v2.utils.getConversationKey(senderSecret, recipientPubkey);
    return nip44.v2.encrypt(content, conversationKey);
}
/**
 * Decrypt content from a sender.
 */
export function decryptFromSender(encrypted, recipientSecret, senderPubkey) {
    const conversationKey = nip44.v2.utils.getConversationKey(recipientSecret, senderPubkey);
    return nip44.v2.decrypt(encrypted, conversationKey);
}
//# sourceMappingURL=nip44.js.map