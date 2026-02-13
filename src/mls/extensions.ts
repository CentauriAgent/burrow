/**
 * Marmot Group Data Extension (0xF2EE) — TLS serialization.
 * Per MIP-01: TLS presentation language serialization with proper length prefixes.
 */

import { MARMOT_EXTENSION_ID } from '../types/index.js';
import type { MarmotGroupData } from '../types/index.js';

/**
 * TLS-encode a uint16 (2 bytes big-endian).
 */
function encodeUint16(value: number): Uint8Array {
  const buf = new Uint8Array(2);
  buf[0] = (value >> 8) & 0xff;
  buf[1] = value & 0xff;
  return buf;
}

function decodeUint16(data: Uint8Array, offset: number): [number, number] {
  return [(data[offset] << 8) | data[offset + 1], offset + 2];
}

/**
 * TLS-encode a variable-length opaque<0..2^16-1>.
 */
function encodeOpaque16(data: Uint8Array): Uint8Array {
  const len = encodeUint16(data.length);
  const result = new Uint8Array(2 + data.length);
  result.set(len, 0);
  result.set(data, 2);
  return result;
}

function decodeOpaque16(data: Uint8Array, offset: number): [Uint8Array, number] {
  const [len, newOffset] = decodeUint16(data, offset);
  return [data.slice(newOffset, newOffset + len), newOffset + len];
}

/**
 * Encode MarmotGroupData to TLS binary format per MIP-01.
 */
export function encodeMarmotGroupData(mgd: MarmotGroupData): Uint8Array {
  const encoder = new TextEncoder();
  const parts: Uint8Array[] = [];

  // version: uint16
  parts.push(encodeUint16(mgd.version));

  // nostr_group_id: opaque[32]
  parts.push(mgd.nostrGroupId);

  // name: opaque<0..2^16-1>
  parts.push(encodeOpaque16(encoder.encode(mgd.name)));

  // description: opaque<0..2^16-1>
  parts.push(encodeOpaque16(encoder.encode(mgd.description)));

  // admin_pubkeys: opaque<0..2^16-1> (array of 64-char hex strings)
  const adminBytes = encoder.encode(mgd.adminPubkeys.join(''));
  parts.push(encodeOpaque16(adminBytes));

  // relays: opaque<0..2^16-1> (newline-separated URLs)
  const relayBytes = encoder.encode(mgd.relays.join('\n'));
  parts.push(encodeOpaque16(relayBytes));

  // image_hash: opaque[32]
  parts.push(mgd.imageHash);

  // image_key: opaque[32]
  parts.push(mgd.imageKey);

  // image_nonce: opaque[12]
  parts.push(mgd.imageNonce);

  // Concatenate all parts
  const totalLen = parts.reduce((sum, p) => sum + p.length, 0);
  const result = new Uint8Array(totalLen);
  let offset = 0;
  for (const part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

/**
 * Decode MarmotGroupData from TLS binary format.
 */
export function decodeMarmotGroupData(data: Uint8Array): MarmotGroupData {
  const decoder = new TextDecoder();
  let offset = 0;

  // version
  let version: number;
  [version, offset] = decodeUint16(data, offset);

  // nostr_group_id: 32 bytes fixed
  const nostrGroupId = data.slice(offset, offset + 32);
  offset += 32;

  // name
  let nameBytes: Uint8Array;
  [nameBytes, offset] = decodeOpaque16(data, offset);
  const name = decoder.decode(nameBytes);

  // description
  let descBytes: Uint8Array;
  [descBytes, offset] = decodeOpaque16(data, offset);
  const description = decoder.decode(descBytes);

  // admin_pubkeys
  let adminBytes: Uint8Array;
  [adminBytes, offset] = decodeOpaque16(data, offset);
  const adminStr = decoder.decode(adminBytes);
  const adminPubkeys: string[] = [];
  for (let i = 0; i < adminStr.length; i += 64) {
    adminPubkeys.push(adminStr.slice(i, i + 64));
  }

  // relays
  let relayBytes: Uint8Array;
  [relayBytes, offset] = decodeOpaque16(data, offset);
  const relays = decoder.decode(relayBytes).split('\n').filter(Boolean);

  // image_hash: 32 bytes
  const imageHash = data.slice(offset, offset + 32);
  offset += 32;

  // image_key: 32 bytes
  const imageKey = data.slice(offset, offset + 32);
  offset += 32;

  // image_nonce: 12 bytes
  const imageNonce = data.slice(offset, offset + 12);
  offset += 12;

  return {
    version,
    nostrGroupId,
    name,
    description,
    adminPubkeys,
    relays,
    imageHash,
    imageKey,
    imageNonce,
  };
}

/**
 * Create a Marmot Group Data extension entry for ts-mls.
 */
export function createMarmotExtension(mgd: MarmotGroupData): { extensionType: number; extensionData: Uint8Array } {
  return {
    extensionType: MARMOT_EXTENSION_ID,
    extensionData: encodeMarmotGroupData(mgd),
  };
}
