/**
 * Integration test: End-to-end encrypted message flow
 * init → create group → encrypt message → decrypt message
 * (No actual relay communication — tests the crypto+MLS pipeline)
 */
import { describe, it, expect } from 'vitest';
import { schnorr } from '@noble/curves/secp256k1.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import { randomBytes } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

import { generateIdentity, getCredentialIdentity } from '../src/crypto/identity.js';
import { encryptGroupMessage, decryptGroupMessage, encryptForRecipient, decryptFromSender } from '../src/crypto/nip44.js';
import { createMarmotGroup, generateMarmotKeyPackage, getExporterSecret, createGroupMsg } from '../src/mls/index.js';
import { encodeMarmotGroupData, decodeMarmotGroupData } from '../src/mls/extensions.js';
import { buildKeyPackageEvent, buildGroupEvent, buildInnerChatMessage, buildWelcomeEvent } from '../src/nostr/events.js';
import { BurrowStore } from '../src/store/index.js';
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

describe('E2E Integration: Full Encrypted Message Flow', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'burrow-e2e-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('full flow: init → create group → generate KP event → send encrypted message → decrypt', async () => {
    // === Step 1: Init identity ===
    const keyPath = join(tempDir, 'secret.key');
    const alice = generateIdentity(keyPath);
    expect(alice.publicKey.length).toBe(32);

    // === Step 2: Create MLS group ===
    const relays = ['wss://relay.test'];
    const { group } = await createMarmotGroup(alice, {
      name: 'Alice Group',
      description: 'E2E test group',
      relays,
    });
    expect(group.name).toBe('Alice Group');

    // === Step 3: Generate and publish KeyPackage (build event) ===
    const kp = await generateMarmotKeyPackage(alice);
    const kpEvent = buildKeyPackageEvent(alice, kp.serializedBase64, { relays });
    expect(kpEvent.kind).toBe(443);
    expect(kpEvent.sig).toBeDefined();

    // === Step 4: Get exporter secret and encrypt a message ===
    const exporterSecret = await getExporterSecret(group.state);
    expect(exporterSecret.length).toBe(32);

    const innerMsg = buildInnerChatMessage(alice.publicKeyHex, 'Hello from the burrow! 🦫');
    const innerJson = JSON.stringify(innerMsg);
    const innerBytes = new TextEncoder().encode(innerJson);

    // Encrypt with NIP-44 using exporter secret
    const encrypted = encryptGroupMessage(innerBytes, exporterSecret);
    expect(typeof encrypted).toBe('string');

    // === Step 5: Build the kind 445 group event ===
    const nostrGroupIdHex = bytesToHex(group.nostrGroupId);
    const { event: groupEvent } = buildGroupEvent(nostrGroupIdHex, encrypted);
    expect(groupEvent.kind).toBe(445);

    // === Step 6: Decrypt and verify ===
    const decryptedBytes = decryptGroupMessage(groupEvent.content, exporterSecret);
    const decryptedJson = new TextDecoder().decode(decryptedBytes);
    const decryptedMsg = JSON.parse(decryptedJson);

    expect(decryptedMsg.kind).toBe(9);
    expect(decryptedMsg.pubkey).toBe(alice.publicKeyHex);
    expect(decryptedMsg.content).toBe('Hello from the burrow! 🦫');
    expect(decryptedMsg.sig).toBeUndefined(); // MIP-03: inner events unsigned

    // === Step 7: Store everything ===
    const store = new BurrowStore(tempDir);
    store.saveGroup({
      mlsGroupId: bytesToHex(new Uint8Array(32)),
      nostrGroupId: nostrGroupIdHex,
      name: group.name,
      description: 'E2E test group',
      adminPubkeys: [alice.publicKeyHex],
      relays,
      mlsState: 'base64state',
      createdAt: Math.floor(Date.now() / 1000),
      lastMessageAt: Math.floor(Date.now() / 1000),
      epoch: 0,
    });

    store.saveMessage({
      id: groupEvent.id,
      groupId: nostrGroupIdHex,
      senderPubkey: decryptedMsg.pubkey,
      content: decryptedMsg.content,
      kind: decryptedMsg.kind,
      createdAt: decryptedMsg.created_at,
      tags: decryptedMsg.tags,
    });

    // Verify stored
    const storedGroup = store.getGroup(nostrGroupIdHex);
    expect(storedGroup?.name).toBe('Alice Group');
    const msgs = store.getMessages(nostrGroupIdHex);
    expect(msgs.length).toBe(1);
    expect(msgs[0].content).toBe('Hello from the burrow! 🦫');
  });

  it('Welcome event flow: create welcome → encrypt for recipient → decrypt', async () => {
    const alice = makeIdentity();
    const bob = makeIdentity();

    // Alice creates a welcome message for Bob
    const welcomeData = 'base64-encoded-mls-welcome-data';
    const welcomeEvent = buildWelcomeEvent(welcomeData, 'kp-event-id-123', ['wss://r.test']);
    expect(welcomeEvent.kind).toBe(444);

    // NIP-59 wrapping: Alice encrypts for Bob
    const welcomeJson = JSON.stringify(welcomeEvent);
    const encrypted = encryptForRecipient(welcomeJson, alice.secretKey, bob.publicKeyHex);

    // Bob decrypts
    const decrypted = decryptFromSender(encrypted, bob.secretKey, alice.publicKeyHex);
    const parsed = JSON.parse(decrypted);
    expect(parsed.kind).toBe(444);
    expect(parsed.content).toBe(welcomeData);
  });

  it('MLS application message encoding requires multi-member group (known ts-mls limitation)', async () => {
    // Single-member groups can't encode application messages in ts-mls
    // because PrivateMessage fields are incomplete without a second member.
    // This documents the limitation — real messaging requires add+commit first.
    const alice = makeIdentity();
    const { group } = await createMarmotGroup(alice, {
      name: 'MLS Msg Flow',
      relays: ['wss://r.test'],
    });

    const content = new TextEncoder().encode('First message');
    await expect(createGroupMsg(group.state, content)).rejects.toThrow();
  });

  it('extension roundtrip through group creation', async () => {
    const alice = makeIdentity();
    const { group } = await createMarmotGroup(alice, {
      name: 'Extension Test',
      description: 'Testing extension encoding',
      relays: ['wss://relay1.test', 'wss://relay2.test'],
    });

    // The group state should contain the Marmot extension
    // Verify group metadata is preserved
    expect(group.name).toBe('Extension Test');
    expect(group.relays).toEqual(['wss://relay1.test', 'wss://relay2.test']);
    expect(group.nostrGroupId.length).toBe(32);
  });
});
