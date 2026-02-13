/**
 * `burrow invite <pubkey>` — Invite a user to a group by fetching their KeyPackage.
 */
import { join } from 'node:path';
import { loadIdentity, encryptForRecipient } from '../crypto/index.js';
import { addMember, deserializeGroupState, serializeGroupState, } from '../mls/index.js';
import { RelayPool, buildWelcomeEvent } from '../nostr/index.js';
import { BurrowStore } from '../store/index.js';
import { MARMOT_KINDS, DEFAULT_RELAYS } from '../types/index.js';
import { decodeMlsMessage, encodeMlsMessage, bytesToBase64 } from 'ts-mls';
import { hexToBytes } from '@noble/hashes/utils.js';
export async function inviteCommand(opts) {
    const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
    console.log(`🦫 Inviting ${opts.inviteePubkey.slice(0, 16)}... to group...\n`);
    const identity = loadIdentity(opts.keyPath);
    const store = new BurrowStore(dataDir);
    // Find the group
    const group = store.getGroup(opts.groupId);
    if (!group) {
        console.error(`❌ Group not found: ${opts.groupId}`);
        process.exit(1);
    }
    const relays = group.relays.length > 0 ? group.relays : DEFAULT_RELAYS;
    // Fetch invitee's KeyPackage from relays
    console.log('📡 Fetching invitee KeyPackage...');
    const pool = new RelayPool(relays);
    let keyPackageEvent;
    try {
        const events = await pool.query([{
                kinds: [MARMOT_KINDS.KEY_PACKAGE],
                authors: [opts.inviteePubkey],
                limit: 1,
            }]);
        if (events.length === 0) {
            console.error(`❌ No KeyPackage found for ${opts.inviteePubkey}. They need to run 'burrow init' first.`);
            pool.close();
            process.exit(1);
        }
        keyPackageEvent = events[0];
        console.log(`  Found KeyPackage: ${keyPackageEvent.id}`);
    }
    catch (e) {
        console.error(`❌ Error fetching KeyPackage: ${e.message}`);
        pool.close();
        process.exit(1);
    }
    // Decode the KeyPackage
    const encoding = keyPackageEvent.tags.find((t) => t[0] === 'encoding')?.[1] || 'hex';
    let kpBytes;
    if (encoding === 'base64') {
        kpBytes = Uint8Array.from(Buffer.from(keyPackageEvent.content, 'base64'));
    }
    else {
        kpBytes = hexToBytes(keyPackageEvent.content);
    }
    const decoded = decodeMlsMessage(kpBytes, 0);
    if (!decoded) {
        console.error('❌ Failed to decode KeyPackage');
        pool.close();
        process.exit(1);
    }
    const [mlsMessage] = decoded;
    if (mlsMessage.wireformat !== 'mls_key_package') {
        console.error('❌ Invalid KeyPackage format');
        pool.close();
        process.exit(1);
    }
    // Load MLS group state
    const mlsState = store.getMlsState(opts.groupId);
    if (!mlsState) {
        console.error('❌ MLS state not found for group');
        pool.close();
        process.exit(1);
    }
    const groupState = deserializeGroupState(mlsState);
    // Add member
    console.log('🔐 Adding member to MLS group...');
    const commitResult = await addMember(groupState, mlsMessage.keyPackage);
    // Build and send Welcome via NIP-59 gift-wrap
    if (commitResult.welcome) {
        const welcomeBytes = encodeMlsMessage(commitResult.welcome);
        const welcomeBase64 = bytesToBase64(welcomeBytes);
        const welcomeEvent = buildWelcomeEvent(welcomeBase64, keyPackageEvent.id, relays);
        const welcomeJson = JSON.stringify(welcomeEvent);
        // Gift-wrap the welcome for the invitee
        console.log('🎁 Gift-wrapping Welcome event...');
        // Use NIP-44 encryption to encrypt for recipient
        const encrypted = encryptForRecipient(welcomeJson, identity.secretKey, opts.inviteePubkey);
        // Publish as a gift-wrapped event (kind 1059)
        const { event: giftWrap } = await (async () => {
            const { createSignedEvent } = await import('../nostr/relay.js');
            const { randomBytes } = await import('node:crypto');
            const ephemeral = new Uint8Array(randomBytes(32));
            return {
                event: createSignedEvent(1059, encrypted, [
                    ['p', opts.inviteePubkey],
                ], ephemeral),
            };
        })();
        console.log('📡 Publishing Welcome...');
        await pool.publish(giftWrap);
        console.log(`  Welcome event sent to ${opts.inviteePubkey.slice(0, 16)}...`);
    }
    // Save updated group state
    if (commitResult.newState) {
        const newEncodedState = serializeGroupState(commitResult.newState);
        store.saveMlsState(opts.groupId, newEncodedState);
        group.epoch += 1;
        group.mlsState = Buffer.from(newEncodedState).toString('base64');
        store.saveGroup(group);
    }
    pool.close();
    console.log(`\n✅ Invited ${opts.inviteePubkey.slice(0, 16)}... to "${group.name}"`);
}
//# sourceMappingURL=invite.js.map