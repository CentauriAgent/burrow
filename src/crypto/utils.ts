/**
 * Hex/bytes utilities - wrapping @noble/hashes to avoid module resolution issues.
 */

// @ts-ignore - module resolution for @noble/hashes subpaths
import { bytesToHex as _bytesToHex, hexToBytes as _hexToBytes } from '@noble/hashes/utils.js';

export const bytesToHex: (bytes: Uint8Array) => string = _bytesToHex;
export const hexToBytes: (hex: string) => Uint8Array = _hexToBytes;
