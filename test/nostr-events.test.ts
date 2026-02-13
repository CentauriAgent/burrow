import { describe, it, expect } from 'vitest';
import { schnorr } from '@noble/curves/secp256k1.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import { randomBytes } from 'node:crypto';
import {
  buildKeyPackageEvent,
  buildGroupEvent,
  buildInnerChatMessage,
  buildWelcomeEvent,
} from '../src/nostr/events.js';
import { MARMOT_KINDS } from '../src/types/index.js';
import type { NostrIdentity } from '../src/crypto/identity.js';

function makeIdentity(): NostrIdentity {
  const secretKey = new Uint8Array(randomBytes(32));
  const publicKey = schnorr.getPublicKey(secretKey);
  return {
    secretKey,
    publicKey,
    publicKeyHex: bytesToHex(publicKey),
    secretKeyHex: bytesToHex(secretKey),
  };
}

describe('Kind 443 — KeyPackage Event', () => {
  it('should create a valid signed event', () => {
    const id = makeIdentity();
    const event = buildKeyPackageEvent(id, 'base64keypackagedata==', {
      relays: ['wss://relay1.test'],
    });

    expect(event.kind).toBe(443);
    expect(event.content).toBe('base64keypackagedata==');
    expect(event.pubkey).toBe(id.publicKeyHex);
    expect(event.sig).toBeDefined();
    expect(event.id).toBeDefined();

    // Check required tags
    const tagMap = new Map(event.tags.map((t: string[]) => [t[0], t]));
    expect(tagMap.get('mls_protocol_version')?.[1]).toBe('1.0');
    expect(tagMap.get('mls_ciphersuite')?.[1]).toBe('0x0001');
    expect(tagMap.get('encoding')?.[1]).toBe('base64');
    expect(tagMap.has('-')).toBe(true); // NIP-70
    
    const relayTag = event.tags.find((t: string[]) => t[0] === 'relays');
    expect(relayTag).toContain('wss://relay1.test');
  });

  it('should include client tag when provided', () => {
    const id = makeIdentity();
    const event = buildKeyPackageEvent(id, 'data', {
      relays: ['wss://r.test'],
      client: 'burrow/0.1.0',
    });
    const clientTag = event.tags.find((t: string[]) => t[0] === 'client');
    expect(clientTag?.[1]).toBe('burrow/0.1.0');
  });
});

describe('Kind 445 — Group Event', () => {
  it('should create event with ephemeral key', () => {
    const groupId = 'ab'.repeat(32);
    const { event, ephemeralSecret } = buildGroupEvent(groupId, 'encrypted-content');

    expect(event.kind).toBe(445);
    expect(event.content).toBe('encrypted-content');
    expect(ephemeralSecret).toBeInstanceOf(Uint8Array);
    expect(ephemeralSecret.length).toBe(32);

    // pubkey should NOT be the caller's — it's ephemeral
    expect(event.pubkey).toBeDefined();
    expect(event.sig).toBeDefined();

    const hTag = event.tags.find((t: string[]) => t[0] === 'h');
    expect(hTag?.[1]).toBe(groupId);
  });
});

describe('Inner Chat Message (kind 9)', () => {
  it('should create unsigned event', () => {
    const pubkey = 'cc'.repeat(32);
    const msg = buildInnerChatMessage(pubkey, 'Hello marmots!');

    expect(msg.kind).toBe(9);
    expect(msg.pubkey).toBe(pubkey);
    expect(msg.content).toBe('Hello marmots!');
    expect(msg.sig).toBeUndefined(); // MUST NOT be signed
    expect(msg.created_at).toBeGreaterThan(0);
  });

  it('should include reply tag when provided', () => {
    const msg = buildInnerChatMessage('dd'.repeat(32), 'reply', 'eventid123');
    const eTag = msg.tags.find((t: string[]) => t[0] === 'e');
    expect(eTag?.[1]).toBe('eventid123');
    expect(eTag?.[3]).toBe('reply');
  });

  it('should have no tags when no reply', () => {
    const msg = buildInnerChatMessage('ee'.repeat(32), 'no reply');
    expect(msg.tags).toEqual([]);
  });
});

describe('Kind 444 — Welcome Event', () => {
  it('should create unsigned event with correct tags', () => {
    const event = buildWelcomeEvent('welcomebase64==', 'kpeventid123', ['wss://r.test']);

    expect(event.kind).toBe(444);
    expect(event.content).toBe('welcomebase64==');
    expect(event.sig).toBeUndefined(); // unsigned per MIP-02

    const eTag = event.tags.find((t: string[]) => t[0] === 'e');
    expect(eTag?.[1]).toBe('kpeventid123');

    const relayTag = event.tags.find((t: string[]) => t[0] === 'relays');
    expect(relayTag).toContain('wss://r.test');

    const encTag = event.tags.find((t: string[]) => t[0] === 'encoding');
    expect(encTag?.[1]).toBe('base64');
  });
});

describe('Marmot Kinds Constants', () => {
  it('should have correct kind values per MIP spec', () => {
    expect(MARMOT_KINDS.KEY_PACKAGE).toBe(443);
    expect(MARMOT_KINDS.WELCOME).toBe(444);
    expect(MARMOT_KINDS.GROUP_MESSAGE).toBe(445);
    expect(MARMOT_KINDS.KEY_PACKAGE_RELAY_LIST).toBe(10051);
  });
});
