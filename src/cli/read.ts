/**
 * `burrow read` — Read messages from a group.
 * `burrow listen` — Listen for new messages in real-time.
 */

import { join } from 'node:path';
import { loadIdentity } from '../crypto/index.js';
import { decryptGroupMessage } from '../crypto/nip44.js';
import {
  getExporterSecret,
  processGroupMessage,
  deserializeGroupState,
  serializeGroupState,
} from '../mls/index.js';
import { RelayPool } from '../nostr/index.js';
import { BurrowStore } from '../store/index.js';
import { MARMOT_KINDS, DEFAULT_RELAYS } from '../types/index.js';
import { hexToBytes } from '@noble/hashes/utils.js';

export function readCommand(opts: {
  groupId: string;
  limit?: number;
  dataDir?: string;
}): void {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const store = new BurrowStore(dataDir);
  const limit = opts.limit || 50;

  const group = store.getGroup(opts.groupId);
  if (!group) {
    console.error(`❌ Group not found: ${opts.groupId}`);
    process.exit(1);
  }

  const messages = store.getMessages(opts.groupId, limit);

  if (messages.length === 0) {
    console.log(`No messages in "${group.name}" yet.`);
    return;
  }

  console.log(`📬 ${group.name} (${messages.length} messages):\n`);
  for (const msg of messages) {
    const time = new Date(msg.createdAt * 1000).toLocaleTimeString();
    const sender = msg.senderPubkey.slice(0, 8);
    console.log(`  [${time}] ${sender}...: ${msg.content}`);
  }
}

export async function listenCommand(opts: {
  groupId: string;
  keyPath?: string;
  dataDir?: string;
}): Promise<void> {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const identity = loadIdentity(opts.keyPath);
  const store = new BurrowStore(dataDir);

  const group = store.getGroup(opts.groupId);
  if (!group) {
    console.error(`❌ Group not found: ${opts.groupId}`);
    process.exit(1);
  }

  const relays = group.relays.length > 0 ? group.relays : DEFAULT_RELAYS;

  console.log(`👂 Listening for messages in "${group.name}"...`);
  console.log('   Press Ctrl+C to stop.\n');

  const pool = new RelayPool(relays);

  // Subscribe to kind 445 events for this group
  pool.subscribe(
    [{
      kinds: [MARMOT_KINDS.GROUP_MESSAGE],
      '#h': [group.nostrGroupId],
      since: Math.floor(Date.now() / 1000),
    }],
    async (event: any) => {
      try {
        // Load current MLS state
        const mlsStateBytes = store.getMlsState(opts.groupId);
        if (!mlsStateBytes) return;

        const groupState = deserializeGroupState(mlsStateBytes);
        const exporterSecret = await getExporterSecret(groupState);

        // Decrypt NIP-44 layer
        const mlsBytes = decryptGroupMessage(event.content, exporterSecret);

        // Process MLS message
        const { result, newState } = await processGroupMessage(groupState, mlsBytes);

        // If it's an application message, extract the inner event
        if (result.content) {
          const innerEvent = JSON.parse(new TextDecoder().decode(result.content));
          const time = new Date().toLocaleTimeString();
          const sender = innerEvent.pubkey?.slice(0, 8) || '???';

          console.log(`  [${time}] ${sender}...: ${innerEvent.content}`);

          // Store
          store.saveMessage({
            id: event.id,
            groupId: opts.groupId,
            senderPubkey: innerEvent.pubkey || '',
            content: innerEvent.content,
            kind: innerEvent.kind,
            createdAt: innerEvent.created_at,
            tags: innerEvent.tags || [],
          });

          // Save updated state
          const newEncoded = serializeGroupState(newState);
          store.saveMlsState(opts.groupId, newEncoded);
        }
      } catch (err: any) {
        console.error(`  ⚠️ Failed to decrypt message: ${err.message}`);
      }
    },
    () => {
      console.log('  (Connected, waiting for messages...)');
    },
  );

  // Keep alive
  await new Promise(() => {});
}
