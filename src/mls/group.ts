/**
 * MLS Group management per MIP-01, MIP-02, MIP-03.
 */

import {
  createGroup,
  createApplicationMessage,
  createCommit,
  processMessage,
  encodeGroupState,
  decodeGroupState,
  getCiphersuiteFromName,
  getCiphersuiteImpl,
  encodeMlsMessage,
  decodeMlsMessage,
  bytesToBase64,
  mlsExporter,
  encodeRequiredCapabilities,
  defaultCapabilities,
  defaultLifetime,
  generateKeyPackage,
  makePskIndex,
  type GroupState,
  type ClientState,
  type CiphersuiteName,
  type KeyPackage,
  type Extension,
  type CreateCommitResult,
} from 'ts-mls';
import { randomBytes } from 'node:crypto';
import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
import {
  MARMOT_EXTENSION_ID,
  LAST_RESORT_EXTENSION_ID,
  type MarmotGroupData,
} from '../types/index.js';
import { encodeMarmotGroupData, createMarmotExtension } from './extensions.js';
import type { NostrIdentity } from '../crypto/identity.js';
import { getCredentialIdentity } from '../crypto/identity.js';
import { generateMarmotKeyPackage } from './keypackage.js';

export interface BurrowGroup {
  state: GroupState;
  nostrGroupId: Uint8Array;
  name: string;
  relays: string[];
}

/**
 * Create a new MLS group per MIP-01.
 */
export async function createMarmotGroup(
  identity: NostrIdentity,
  opts: {
    name: string;
    description?: string;
    relays: string[];
    ciphersuiteName?: CiphersuiteName;
  }
): Promise<{ group: BurrowGroup; encodedState: Uint8Array }> {
  const ciphersuiteName = opts.ciphersuiteName || 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);

  const mlsGroupId = new Uint8Array(randomBytes(32));
  const nostrGroupId = new Uint8Array(randomBytes(32));

  const marmotData: MarmotGroupData = {
    version: 1,
    nostrGroupId,
    name: opts.name,
    description: opts.description || '',
    adminPubkeys: [identity.publicKeyHex],
    relays: opts.relays,
    imageHash: new Uint8Array(32),
    imageKey: new Uint8Array(32),
    imageNonce: new Uint8Array(12),
  };

  const marmotExtension = createMarmotExtension(marmotData);
  const groupExtensions: Extension[] = [marmotExtension];

  const kpResult = await generateMarmotKeyPackage(identity, ciphersuiteName);

  const state = await createGroup(
    mlsGroupId,
    kpResult.keyPackage,
    kpResult.privateKeyPackage,
    groupExtensions,
    cs,
  );

  const encodedState = encodeGroupState(state as any);

  return {
    group: { state, nostrGroupId, name: opts.name, relays: opts.relays },
    encodedState,
  };
}

/**
 * Add a member to the group by their KeyPackage.
 */
export async function addMember(
  state: GroupState,
  memberKeyPackage: KeyPackage,
  ciphersuiteName: CiphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
): Promise<CreateCommitResult> {
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);
  const pskIndex = makePskIndex(state as any, {});

  return await createCommit(
    { state: state as any, pskIndex, cipherSuite: cs },
    { extraProposals: [{ proposalType: 'add', keyPackage: memberKeyPackage }] as any },
  );
}

/**
 * Create an encrypted application message per MIP-03.
 */
export async function createGroupMsg(
  state: GroupState,
  content: Uint8Array,
  ciphersuiteName: CiphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
): Promise<{ message: Uint8Array; newState: GroupState }> {
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);

  const result = await createApplicationMessage(state as any, content, cs);

  return {
    message: encodeMlsMessage(result.privateMessage as any),
    newState: result.newState as any,
  };
}

/**
 * Process an incoming MLS message.
 */
export async function processGroupMessage(
  state: GroupState,
  messageBytes: Uint8Array,
  ciphersuiteName: CiphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
): Promise<any> {
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);

  const decoded = decodeMlsMessage(messageBytes, 0);
  if (!decoded) throw new Error('Failed to decode MLS message');
  const [mlsMessage] = decoded;
  const pskIndex = makePskIndex(state as any, {});

  const { acceptAll } = await import('ts-mls');
  const result = await processMessage(mlsMessage as any, state as any, pskIndex, acceptAll, cs);
  return result;
}

/**
 * Get the exporter_secret for the current epoch.
 */
export async function getExporterSecret(
  state: GroupState,
  ciphersuiteName: CiphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519',
): Promise<Uint8Array> {
  const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
  const cs = await getCiphersuiteImpl(ciphersuite);

  return await mlsExporter(
    (state as any).keySchedule.exporterSecret,
    'marmot_exporter',
    new Uint8Array(0),
    32,
    cs,
  );
}

export function serializeGroupState(state: GroupState): Uint8Array {
  return encodeGroupState(state as any);
}

export function deserializeGroupState(data: Uint8Array): GroupState {
  const decoded = decodeGroupState(data, 0);
  if (!decoded) throw new Error('Failed to decode group state');
  const state = decoded[0] as any;

  // ts-mls encodeGroupState doesn't persist clientConfig — restore defaults
  if (!state.clientConfig) {
    state.clientConfig = {
      paddingConfig: { type: 'none' },
    };
  }

  return state as GroupState;
}
