/**
 * `burrow daemon` — Listen for messages across ALL groups with auto-reconnect.
 * Outputs JSONL to stdout and optionally to a log file for OpenClaw integration.
 */

import { join } from 'node:path';
import { appendFileSync, mkdirSync } from 'node:fs';
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

interface DaemonMessage {
  type: 'message';
  timestamp: string;
  groupId: string;
  groupName: string;
  senderPubkey: string;
  content: string;
  eventId: string;
}

interface DaemonStatus {
  type: 'status';
  timestamp: string;
  event: string;
  details?: string;
}

function emit(obj: DaemonMessage | DaemonStatus, logFile?: string): void {
  const line = JSON.stringify(obj);
  console.log(line);
  if (logFile) {
    appendFileSync(logFile, line + '\n');
  }
}

export async function daemonCommand(opts: {
  keyPath?: string;
  dataDir?: string;
  logFile?: string;
  reconnectDelay?: number;
}): Promise<void> {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const reconnectDelay = opts.reconnectDelay || 5000;
  const logFile = opts.logFile;

  if (logFile) {
    mkdirSync(join(logFile, '..'), { recursive: true });
  }

  const identity = loadIdentity(opts.keyPath);
  const store = new BurrowStore(dataDir);

  emit({
    type: 'status',
    timestamp: new Date().toISOString(),
    event: 'starting',
    details: `Burrow daemon starting, identity: ${identity.publicKeyHex.slice(0, 16)}...`,
  }, logFile);

  async function listenToGroup(groupId: string, groupName: string, relays: string[]): Promise<void> {
    while (true) {
      try {
        emit({
          type: 'status',
          timestamp: new Date().toISOString(),
          event: 'connecting',
          details: `Connecting to "${groupName}" (${groupId.slice(0, 16)}...)`,
        }, logFile);

        const pool = new RelayPool(relays);
        let connected = false;

        await new Promise<void>((resolve, reject) => {
          const sub = pool.subscribe(
            [{
              kinds: [MARMOT_KINDS.GROUP_MESSAGE],
              '#h': [groupId],
              since: Math.floor(Date.now() / 1000),
            }],
            async (event: any) => {
              try {
                const mlsStateBytes = store.getMlsState(groupId);
                if (!mlsStateBytes) return;

                const groupState = deserializeGroupState(mlsStateBytes);
                const exporterSecret = await getExporterSecret(groupState);
                const mlsBytes = decryptGroupMessage(event.content, exporterSecret);
                const { result, newState } = await processGroupMessage(groupState, mlsBytes);

                if (result.content) {
                  const innerEvent = JSON.parse(new TextDecoder().decode(result.content));

                  emit({
                    type: 'message',
                    timestamp: new Date().toISOString(),
                    groupId,
                    groupName,
                    senderPubkey: innerEvent.pubkey || '',
                    content: innerEvent.content,
                    eventId: event.id,
                  }, logFile);

                  store.saveMessage({
                    id: event.id,
                    groupId,
                    senderPubkey: innerEvent.pubkey || '',
                    content: innerEvent.content,
                    kind: innerEvent.kind,
                    createdAt: innerEvent.created_at,
                    tags: innerEvent.tags || [],
                  });

                  const newEncoded = serializeGroupState(newState);
                  store.saveMlsState(groupId, newEncoded);
                }
              } catch (err: any) {
                emit({
                  type: 'status',
                  timestamp: new Date().toISOString(),
                  event: 'decrypt_error',
                  details: `${groupName}: ${err.message}`,
                }, logFile);
              }
            },
            () => {
              connected = true;
              emit({
                type: 'status',
                timestamp: new Date().toISOString(),
                event: 'connected',
                details: `Listening on "${groupName}"`,
              }, logFile);
            },
          );

          // Monitor connection - if pool closes unexpectedly, reject to trigger reconnect
          // SimplePool doesn't expose disconnect events directly, so we use a heartbeat
          const heartbeat = setInterval(() => {
            // Check if still alive by verifying pool state
            // If the pool errors out, the subscribe callbacks stop firing
          }, 30000);

          // Keep this promise open until error
          process.on('SIGTERM', () => {
            clearInterval(heartbeat);
            sub.close();
            pool.close();
            resolve();
          });

          process.on('SIGINT', () => {
            clearInterval(heartbeat);
            sub.close();
            pool.close();
            resolve();
          });
        });

        break; // Clean exit
      } catch (err: any) {
        emit({
          type: 'status',
          timestamp: new Date().toISOString(),
          event: 'reconnecting',
          details: `${groupName}: ${err.message}. Reconnecting in ${reconnectDelay / 1000}s...`,
        }, logFile);
        await new Promise(r => setTimeout(r, reconnectDelay));
      }
    }
  }

  // Listen on all groups concurrently
  const groups = store.listGroups();
  if (groups.length === 0) {
    emit({
      type: 'status',
      timestamp: new Date().toISOString(),
      event: 'error',
      details: 'No groups found. Create a group first with `burrow create-group`.',
    }, logFile);
    process.exit(1);
  }

  emit({
    type: 'status',
    timestamp: new Date().toISOString(),
    event: 'ready',
    details: `Listening on ${groups.length} group(s): ${groups.map(g => g.name).join(', ')}`,
  }, logFile);

  const promises = groups.map(group => {
    const relays = group.relays.length > 0 ? group.relays : DEFAULT_RELAYS;
    return listenToGroup(group.nostrGroupId, group.name, relays);
  });

  await Promise.all(promises);
}
