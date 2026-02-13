import { describe, it, expect } from 'vitest';
import { randomBytes } from 'node:crypto';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
import { schnorr } from '@noble/curves/secp256k1.js';
import {
  encryptGroupMessage,
  decryptGroupMessage,
  encryptForRecipient,
  decryptFromSender,
} from '../src/crypto/nip44.js';
import { generateIdentity, loadIdentity, getCredentialIdentity } from '../src/crypto/identity.js';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

describe('Identity Management', () => {
  let tempDir: string;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'burrow-test-'));
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  it('should generate a new identity with valid keys', () => {
    const keyPath = join(tempDir, 'test.key');
    const id = generateIdentity(keyPath);

    expect(id.secretKey).toBeInstanceOf(Uint8Array);
    expect(id.secretKey.length).toBe(32);
    expect(id.publicKey).toBeInstanceOf(Uint8Array);
    expect(id.publicKey.length).toBe(32);
    expect(id.publicKeyHex).toHaveLength(64);
    expect(id.secretKeyHex).toHaveLength(64);
    expect(existsSync(keyPath)).toBe(true);
  });

  it('should load a generated identity from file', () => {
    const keyPath = join(tempDir, 'test.key');
    const original = generateIdentity(keyPath);
    const loaded = loadIdentity(keyPath);

    expect(loaded.publicKeyHex).toBe(original.publicKeyHex);
    expect(loaded.secretKeyHex).toBe(original.secretKeyHex);
  });

  it('should throw when key file does not exist', () => {
    expect(() => loadIdentity(join(tempDir, 'nonexistent.key'))).toThrow('Secret key not found');
  });

  it('should produce valid schnorr public key', () => {
    const keyPath = join(tempDir, 'test.key');
    const id = generateIdentity(keyPath);
    const expectedPub = schnorr.getPublicKey(id.secretKey);
    expect(bytesToHex(id.publicKey)).toBe(bytesToHex(expectedPub));
  });

  it('getCredentialIdentity returns raw 32-byte pubkey', () => {
    const keyPath = join(tempDir, 'test.key');
    const id = generateIdentity(keyPath);
    const cred = getCredentialIdentity(id);
    expect(cred).toBe(id.publicKey);
    expect(cred.length).toBe(32);
  });

  it('should create nested directories for key path', () => {
    const keyPath = join(tempDir, 'deep', 'nested', 'test.key');
    const id = generateIdentity(keyPath);
    expect(existsSync(keyPath)).toBe(true);
    expect(id.secretKey.length).toBe(32);
  });
});

describe('NIP-44 Group Encryption', () => {
  it('should encrypt and decrypt group message roundtrip', () => {
    // Generate a valid secp256k1 private key
    const exporterSecret = new Uint8Array(randomBytes(32));
    const plaintext = new TextEncoder().encode('Hello, encrypted world!');

    const encrypted = encryptGroupMessage(plaintext, exporterSecret);
    expect(typeof encrypted).toBe('string');
    expect(encrypted.length).toBeGreaterThan(0);

    const decrypted = decryptGroupMessage(encrypted, exporterSecret);
    expect(new TextDecoder().decode(decrypted)).toBe('Hello, encrypted world!');
  });

  it('should reject empty content (NIP-44 requires 1-65535 bytes)', () => {
    const exporterSecret = new Uint8Array(randomBytes(32));
    const plaintext = new TextEncoder().encode('');

    expect(() => encryptGroupMessage(plaintext, exporterSecret)).toThrow();
  });

  it('should handle unicode content', () => {
    const exporterSecret = new Uint8Array(randomBytes(32));
    const text = '🦫 Marmot says: こんにちは 世界! 🌍';
    const plaintext = new TextEncoder().encode(text);

    const encrypted = encryptGroupMessage(plaintext, exporterSecret);
    const decrypted = decryptGroupMessage(encrypted, exporterSecret);
    expect(new TextDecoder().decode(decrypted)).toBe(text);
  });

  it('should fail to decrypt with wrong key', () => {
    const key1 = new Uint8Array(randomBytes(32));
    const key2 = new Uint8Array(randomBytes(32));
    const plaintext = new TextEncoder().encode('secret');

    const encrypted = encryptGroupMessage(plaintext, key1);
    expect(() => decryptGroupMessage(encrypted, key2)).toThrow();
  });

  it('should produce different ciphertexts for same plaintext (random nonce)', () => {
    const exporterSecret = new Uint8Array(randomBytes(32));
    const plaintext = new TextEncoder().encode('same message');

    const enc1 = encryptGroupMessage(plaintext, exporterSecret);
    const enc2 = encryptGroupMessage(plaintext, exporterSecret);
    expect(enc1).not.toBe(enc2); // NIP-44 uses random nonce
  });
});

describe('NIP-44 Recipient Encryption (NIP-59 wrapping)', () => {
  it('should encrypt/decrypt between sender and recipient', () => {
    const senderSecret = new Uint8Array(randomBytes(32));
    const recipientSecret = new Uint8Array(randomBytes(32));
    const senderPub = bytesToHex(schnorr.getPublicKey(senderSecret));
    const recipientPub = bytesToHex(schnorr.getPublicKey(recipientSecret));

    const message = 'Welcome to the group!';
    const encrypted = encryptForRecipient(message, senderSecret, recipientPub);
    const decrypted = decryptFromSender(encrypted, recipientSecret, senderPub);
    expect(decrypted).toBe(message);
  });

  it('should fail with wrong recipient key', () => {
    const senderSecret = new Uint8Array(randomBytes(32));
    const recipientPub = bytesToHex(schnorr.getPublicKey(new Uint8Array(randomBytes(32))));
    const wrongSecret = new Uint8Array(randomBytes(32));
    const senderPub = bytesToHex(schnorr.getPublicKey(senderSecret));

    const encrypted = encryptForRecipient('secret', senderSecret, recipientPub);
    expect(() => decryptFromSender(encrypted, wrongSecret, senderPub)).toThrow();
  });
});
