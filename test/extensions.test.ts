import { describe, it, expect } from 'vitest';
import { encodeMarmotGroupData, decodeMarmotGroupData, createMarmotExtension } from '../src/mls/extensions.js';
import { MARMOT_EXTENSION_ID } from '../src/types/index.js';
import type { MarmotGroupData } from '../src/types/index.js';
import { randomBytes } from 'node:crypto';

function makeMGD(overrides: Partial<MarmotGroupData> = {}): MarmotGroupData {
  return {
    version: 1,
    nostrGroupId: new Uint8Array(randomBytes(32)),
    name: 'Test Group',
    description: 'A test group for marmots',
    adminPubkeys: ['a'.repeat(64), 'b'.repeat(64)],
    relays: ['wss://relay1.example.com', 'wss://relay2.example.com'],
    imageHash: new Uint8Array(32),
    imageKey: new Uint8Array(32),
    imageNonce: new Uint8Array(12),
    ...overrides,
  };
}

describe('Marmot Group Data Extension Encoding', () => {
  it('should encode and decode roundtrip', () => {
    const mgd = makeMGD();
    const encoded = encodeMarmotGroupData(mgd);
    expect(encoded).toBeInstanceOf(Uint8Array);
    expect(encoded.length).toBeGreaterThan(0);

    const decoded = decodeMarmotGroupData(encoded);
    expect(decoded.version).toBe(mgd.version);
    expect(decoded.name).toBe(mgd.name);
    expect(decoded.description).toBe(mgd.description);
    expect(decoded.adminPubkeys).toEqual(mgd.adminPubkeys);
    expect(decoded.relays).toEqual(mgd.relays);
    expect(Buffer.from(decoded.nostrGroupId)).toEqual(Buffer.from(mgd.nostrGroupId));
    expect(Buffer.from(decoded.imageHash)).toEqual(Buffer.from(mgd.imageHash));
    expect(Buffer.from(decoded.imageKey)).toEqual(Buffer.from(mgd.imageKey));
    expect(Buffer.from(decoded.imageNonce)).toEqual(Buffer.from(mgd.imageNonce));
  });

  it('should handle empty strings', () => {
    const mgd = makeMGD({ name: '', description: '' });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.name).toBe('');
    expect(decoded.description).toBe('');
  });

  it('should handle unicode in name/description', () => {
    const mgd = makeMGD({ name: '🦫 Marmot Grüße', description: '日本語テスト' });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.name).toBe('🦫 Marmot Grüße');
    expect(decoded.description).toBe('日本語テスト');
  });

  it('should handle single admin', () => {
    const mgd = makeMGD({ adminPubkeys: ['c'.repeat(64)] });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.adminPubkeys).toEqual(['c'.repeat(64)]);
  });

  it('should handle no admins', () => {
    const mgd = makeMGD({ adminPubkeys: [] });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.adminPubkeys).toEqual([]);
  });

  it('should handle single relay', () => {
    const mgd = makeMGD({ relays: ['wss://single.relay'] });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.relays).toEqual(['wss://single.relay']);
  });

  it('should handle no relays', () => {
    const mgd = makeMGD({ relays: [] });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(decoded.relays).toEqual([]);
  });

  it('createMarmotExtension should have correct extension type', () => {
    const mgd = makeMGD();
    const ext = createMarmotExtension(mgd);
    expect(ext.extensionType).toBe(MARMOT_EXTENSION_ID);
    expect(ext.extensionData).toBeInstanceOf(Uint8Array);
    expect(ext.extensionData.length).toBeGreaterThan(0);
  });

  it('should preserve non-zero image fields', () => {
    const imgHash = new Uint8Array(32).fill(0xab);
    const imgKey = new Uint8Array(32).fill(0xcd);
    const imgNonce = new Uint8Array(12).fill(0xef);
    const mgd = makeMGD({ imageHash: imgHash, imageKey: imgKey, imageNonce: imgNonce });
    const decoded = decodeMarmotGroupData(encodeMarmotGroupData(mgd));
    expect(Buffer.from(decoded.imageHash)).toEqual(Buffer.from(imgHash));
    expect(Buffer.from(decoded.imageKey)).toEqual(Buffer.from(imgKey));
    expect(Buffer.from(decoded.imageNonce)).toEqual(Buffer.from(imgNonce));
  });
});
