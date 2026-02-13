/**
 * Nostr event builders for Marmot protocol event kinds.
 */

import { MARMOT_KINDS } from '../types/index.js';
import { createSignedEvent, createEphemeralSignedEvent } from './relay.js';
import type { NostrIdentity } from '../crypto/identity.js';
import { getCiphersuiteHexId } from '../mls/keypackage.js';
import type { CiphersuiteName } from 'ts-mls';

/**
 * Build a kind 443 KeyPackage event per MIP-00.
 */
export function buildKeyPackageEvent(
  identity: NostrIdentity,
  keyPackageBase64: string,
  opts: {
    ciphersuiteName?: CiphersuiteName;
    relays: string[];
    client?: string;
  }
): any {
  const ciphersuiteName = opts.ciphersuiteName || 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';
  const csHex = getCiphersuiteHexId(ciphersuiteName);

  const tags: string[][] = [
    ['mls_protocol_version', '1.0'],
    ['mls_ciphersuite', csHex],
    ['mls_extensions', '0xf2ee', '0x000a'],
    ['encoding', 'base64'],
    ['relays', ...opts.relays],
    ['-'], // NIP-70: only author can publish
  ];

  if (opts.client) {
    tags.push(['client', opts.client]);
  }

  return createSignedEvent(
    MARMOT_KINDS.KEY_PACKAGE,
    keyPackageBase64,
    tags,
    identity.secretKey,
  );
}

/**
 * Build a kind 445 Group Event (encrypted MLS message) per MIP-03.
 * Uses an ephemeral keypair for publishing.
 */
export function buildGroupEvent(
  nostrGroupIdHex: string,
  encryptedContent: string,
): { event: any; ephemeralSecret: Uint8Array } {
  const tags: string[][] = [
    ['h', nostrGroupIdHex],
  ];

  return createEphemeralSignedEvent(
    MARMOT_KINDS.GROUP_MESSAGE,
    encryptedContent,
    tags,
  );
}

/**
 * Build an unsigned inner application message (kind 9 chat) per MIP-03.
 * Inner events MUST be unsigned and MUST NOT include h tags.
 */
export function buildInnerChatMessage(
  senderPubkeyHex: string,
  text: string,
  replyToId?: string,
): any {
  const tags: string[][] = [];
  if (replyToId) {
    tags.push(['e', replyToId, '', 'reply']);
  }

  return {
    kind: 9,
    pubkey: senderPubkeyHex,
    content: text,
    tags,
    created_at: Math.floor(Date.now() / 1000),
    // NO sig field — per MIP-03 security requirements
  };
}

/**
 * Build a kind 444 Welcome event (unsigned) per MIP-02.
 * This is wrapped in NIP-59 gift-wrapping before sending.
 */
export function buildWelcomeEvent(
  welcomeBase64: string,
  keyPackageEventId: string,
  relays: string[],
): any {
  return {
    kind: MARMOT_KINDS.WELCOME,
    content: welcomeBase64,
    tags: [
      ['e', keyPackageEventId],
      ['relays', ...relays],
      ['encoding', 'base64'],
    ],
    created_at: Math.floor(Date.now() / 1000),
    // NO sig — per MIP-02
  };
}
