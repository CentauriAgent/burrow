/**
 * Burrow type definitions — Marmot Protocol types for Nostr + MLS
 */

// Nostr event kinds for Marmot protocol
export const MARMOT_KINDS = {
  KEY_PACKAGE: 443,
  WELCOME: 444,
  GROUP_MESSAGE: 445,
  KEY_PACKAGE_RELAY_LIST: 10051,
} as const;

// Marmot Group Data Extension ID
export const MARMOT_EXTENSION_ID = 0xf2ee;
export const LAST_RESORT_EXTENSION_ID = 0x000a;

export interface BurrowConfig {
  secretKeyPath: string;
  dataDir: string;
  relays: string[];
  ciphersuite: string;
}

export interface MarmotGroupData {
  version: number; // uint16, currently 1
  nostrGroupId: Uint8Array; // 32 bytes
  name: string;
  description: string;
  adminPubkeys: string[]; // hex-encoded 32-byte pubkeys
  relays: string[];
  imageHash: Uint8Array; // 32 bytes
  imageKey: Uint8Array; // 32 bytes
  imageNonce: Uint8Array; // 12 bytes
}

export interface StoredGroup {
  mlsGroupId: string; // hex of MLS group ID
  nostrGroupId: string; // hex of nostr_group_id from extension
  name: string;
  description: string;
  adminPubkeys: string[];
  relays: string[];
  mlsState: string; // base64 encoded MLS GroupState
  createdAt: number;
  lastMessageAt: number;
  epoch: number;
}

export interface StoredKeyPackage {
  id: string; // nostr event id
  mlsKeyPackage: string; // base64 encoded
  privateKey: string; // base64 encoded private init_key
  createdAt: number;
  isLastResort: boolean;
}

export interface GroupMessage {
  id: string;
  groupId: string;
  senderPubkey: string;
  content: string;
  kind: number;
  createdAt: number;
  tags: string[][];
}

export interface NostrEvent {
  id?: string;
  kind: number;
  created_at: number;
  pubkey: string;
  content: string;
  tags: string[][];
  sig?: string;
}

export const DEFAULT_RELAYS = [
  'wss://relay.ditto.pub',
  'wss://relay.primal.net',
  'wss://nos.lol',
];

export const DEFAULT_CIPHERSUITE = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';
