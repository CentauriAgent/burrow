/**
 * `burrow send` — Send an encrypted message to a group.
 */
import { join } from 'node:path';
import { loadIdentity } from '../crypto/index.js';
import { encryptGroupMessage } from '../crypto/nip44.js';
import { createGroupMsg, getExporterSecret, deserializeGroupState, serializeGroupState, } from '../mls/index.js';
import { RelayPool, buildGroupEvent, buildInnerChatMessage } from '../nostr/index.js';
import { BurrowStore } from '../store/index.js';
import { DEFAULT_RELAYS } from '../types/index.js';
import { AuditLog } from '../security/index.js';
export async function sendCommand(opts) {
    const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
    const identity = loadIdentity(opts.keyPath);
    const store = new BurrowStore(dataDir);
    const group = store.getGroup(opts.groupId);
    if (!group) {
        console.error(`❌ Group not found: ${opts.groupId}`);
        process.exit(1);
    }
    const relays = group.relays.length > 0 ? group.relays : DEFAULT_RELAYS;
    // Load MLS state
    const mlsStateBytes = store.getMlsState(opts.groupId);
    if (!mlsStateBytes) {
        console.error('❌ MLS state not found');
        process.exit(1);
    }
    const groupState = deserializeGroupState(mlsStateBytes);
    // Build the inner unsigned chat message (kind 9 per MIP-03)
    const innerEvent = buildInnerChatMessage(identity.publicKeyHex, opts.message);
    const innerBytes = new TextEncoder().encode(JSON.stringify(innerEvent));
    // Create MLS application message
    console.log('🔐 Encrypting message...');
    const { message: mlsMessage, newState } = await createGroupMsg(groupState, innerBytes);
    // Get exporter_secret for NIP-44 encryption layer
    const exporterSecret = await getExporterSecret(groupState);
    // NIP-44 encrypt the MLS message using exporter_secret per MIP-03
    const encrypted = encryptGroupMessage(mlsMessage, exporterSecret);
    // Build and publish as kind 445 Group Event with ephemeral key
    const { event } = buildGroupEvent(group.nostrGroupId, encrypted);
    const pool = new RelayPool(relays);
    try {
        await pool.publish(event);
        console.log(`✅ Message sent to "${group.name}"`);
        console.log(`   Event: ${event.id}`);
    }
    finally {
        pool.close();
    }
    // Save updated state
    const newEncoded = serializeGroupState(newState);
    store.saveMlsState(opts.groupId, newEncoded);
    group.mlsState = Buffer.from(newEncoded).toString('base64');
    group.lastMessageAt = Math.floor(Date.now() / 1000);
    store.saveGroup(group);
    // Audit log
    const audit = new AuditLog(dataDir);
    audit.logSentMessage({
        groupId: opts.groupId,
        groupName: group.name,
        contentPreview: opts.message.slice(0, 100),
    });
    // Store message locally
    store.saveMessage({
        id: event.id,
        groupId: opts.groupId,
        senderPubkey: identity.publicKeyHex,
        content: opts.message,
        kind: 9,
        createdAt: innerEvent.created_at,
        tags: innerEvent.tags,
    });
}
//# sourceMappingURL=send.js.map