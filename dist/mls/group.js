/**
 * MLS Group management per MIP-01, MIP-02, MIP-03.
 */
import { createGroup, createApplicationMessage, createCommit, processMessage, encodeGroupState, decodeGroupState, getCiphersuiteFromName, getCiphersuiteImpl, encodeMlsMessage, decodeMlsMessage, mlsExporter, makePskIndex, } from 'ts-mls';
import { randomBytes } from 'node:crypto';
import { createMarmotExtension } from './extensions.js';
import { generateMarmotKeyPackage } from './keypackage.js';
/**
 * Create a new MLS group per MIP-01.
 */
export async function createMarmotGroup(identity, opts) {
    const ciphersuiteName = opts.ciphersuiteName || 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';
    const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
    const cs = await getCiphersuiteImpl(ciphersuite);
    const mlsGroupId = new Uint8Array(randomBytes(32));
    const nostrGroupId = new Uint8Array(randomBytes(32));
    const marmotData = {
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
    const groupExtensions = [marmotExtension];
    const kpResult = await generateMarmotKeyPackage(identity, ciphersuiteName);
    const state = await createGroup(mlsGroupId, kpResult.keyPackage, kpResult.privateKeyPackage, groupExtensions, cs);
    const encodedState = encodeGroupState(state);
    return {
        group: { state, nostrGroupId, name: opts.name, relays: opts.relays },
        encodedState,
    };
}
/**
 * Add a member to the group by their KeyPackage.
 */
export async function addMember(state, memberKeyPackage, ciphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
    const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
    const cs = await getCiphersuiteImpl(ciphersuite);
    const pskIndex = makePskIndex(state, {});
    return await createCommit({ state: state, pskIndex, cipherSuite: cs }, { extraProposals: [{ proposalType: 'add', keyPackage: memberKeyPackage }] });
}
/**
 * Create an encrypted application message per MIP-03.
 */
export async function createGroupMsg(state, content, ciphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
    const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
    const cs = await getCiphersuiteImpl(ciphersuite);
    const result = await createApplicationMessage(state, content, cs);
    return {
        message: encodeMlsMessage(result.privateMessage),
        newState: result.newState,
    };
}
/**
 * Process an incoming MLS message.
 */
export async function processGroupMessage(state, messageBytes, ciphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
    const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
    const cs = await getCiphersuiteImpl(ciphersuite);
    const decoded = decodeMlsMessage(messageBytes, 0);
    if (!decoded)
        throw new Error('Failed to decode MLS message');
    const [mlsMessage] = decoded;
    const pskIndex = makePskIndex(state, {});
    const { acceptAll } = await import('ts-mls');
    const result = await processMessage(mlsMessage, state, pskIndex, acceptAll, cs);
    return result;
}
/**
 * Get the exporter_secret for the current epoch.
 */
export async function getExporterSecret(state, ciphersuiteName = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519') {
    const ciphersuite = getCiphersuiteFromName(ciphersuiteName);
    const cs = await getCiphersuiteImpl(ciphersuite);
    return await mlsExporter(state.keySchedule.exporterSecret, 'marmot_exporter', new Uint8Array(0), 32, cs);
}
export function serializeGroupState(state) {
    return encodeGroupState(state);
}
export function deserializeGroupState(data) {
    const decoded = decodeGroupState(data, 0);
    if (!decoded)
        throw new Error('Failed to decode group state');
    const state = decoded[0];
    // ts-mls encodeGroupState doesn't persist clientConfig — restore defaults
    if (!state.clientConfig) {
        state.clientConfig = {
            paddingConfig: { type: 'none' },
        };
    }
    return state;
}
//# sourceMappingURL=group.js.map