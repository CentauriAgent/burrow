/**
 * `burrow daemon` — Listen for messages across ALL groups with auto-reconnect.
 * Enforces access control and maintains audit trail.
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
import { AccessControl, AuditLog } from '../security/index.js';

interface DaemonMessage {
  type: 'message';
  timestamp: string;
  groupId: string;
  groupName: string;
  senderPubkey: string;
  content: string;
  eventId: string;
  allowed: boolean;
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
  noAccessControl?: boolean;
}): Promise<void> {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const reconnectDelay = opts.reconnectDelay || 5000;
  const logFile = opts.logFile;

  if (logFile) {
    mkdirSync(join(logFile, '..'), { recursive: true });
  }

  const identity = loadIdentity(opts.keyPath);
  const store = new BurrowStore(dataDir);
  const audit = new AuditLog(dataDir);

  // Access control — required unless explicitly disabled (for testing only)
  let acl: AccessControl | null = null;
  if (!opts.noAccessControl) {
    try {
      acl = new AccessControl(dataDir);
    } catch (err: any) {
      emit({
        type: 'status',
        timestamp: new Date().toISOString(),
        event: 'error',
        details: `Access control failed: ${err.message}`,
      }, logFile);
      process.exit(1);
    }
  }

  audit.log({
    timestamp: new Date().toISOString(),
    type: 'daemon_start',
    allowed: true,
    details: `Identity: ${identity.publicKeyHex.slice(0, 16)}..., ACL: ${acl ? 'enabled' : 'DISABLED'}`,
  });

  emit({
    type: 'status',
    timestamp: new Date().toISOString(),
    event: 'starting',
    details: `Burrow daemon starting, identity: ${identity.publicKeyHex.slice(0, 16)}..., ACL: ${acl ? 'enabled' : 'DISABLED'}`,
  }, logFile);

  // Graceful shutdown
  const shutdown = () => {
    audit.log({
      timestamp: new Date().toISOString(),
      type: 'daemon_stop',
      allowed: true,
      details: 'Clean shutdown',
    });
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  async function listenToGroup(groupId: string, groupName: string, relays: string[]): Promise<void> {
    // Check group allowlist
    if (acl && !acl.isGroupAllowed(groupId)) {
      audit.log({
        timestamp: new Date().toISOString(),
        type: 'group_rejected',
        groupId,
        groupName,
        allowed: false,
        details: 'Group not in allowlist, skipping',
      });
      emit({
        type: 'status',
        timestamp: new Date().toISOString(),
        event: 'group_skipped',
        details: `"${groupName}" not in allowlist, skipping`,
      }, logFile);
      return;
    }

    while (true) {
      try {
        emit({
          type: 'status',
          timestamp: new Date().toISOString(),
          event: 'connecting',
          details: `Connecting to "${groupName}" (${groupId.slice(0, 16)}...)`,
        }, logFile);

        const pool = new RelayPool(relays);

        await new Promise<void>((resolve) => {
          const sub = pool.subscribe(
            [{
              kinds: [MARMOT_KINDS.GROUP_MESSAGE],
              '#h': [groupId],
              since: Math.floor(Date.now() / 1000),
            }],
            async (event: any) => {
              try {
                // Guard: only process MLS group messages (kind 445)
                if (event.kind !== MARMOT_KINDS.GROUP_MESSAGE) {
                  return;
                }

                const mlsStateBytes = store.getMlsState(groupId);
                if (!mlsStateBytes) return;

                const groupState = deserializeGroupState(mlsStateBytes);
                const exporterSecret = await getExporterSecret(groupState);
                const mlsBytes = decryptGroupMessage(event.content, exporterSecret);

                // Process with error boundary — don't save state if MLS processing fails
                let result: any;
                let newState: any;
                try {
                  const processed = await processGroupMessage(groupState, mlsBytes);
                  result = processed.result;
                  newState = processed.newState;
                } catch (mlsErr: any) {
                  emit({
                    type: 'status',
                    timestamp: new Date().toISOString(),
                    event: 'mls_error',
                    details: `${groupName}: MLS processing failed (state NOT updated): ${mlsErr.message}`,
                  }, logFile);
                  return; // Skip state update to prevent corruption
                }

                if (result.content) {
                  const innerEvent = JSON.parse(new TextDecoder().decode(result.content));
                  const senderPubkey = innerEvent.pubkey || '';
                  const content = innerEvent.content || '';

                  // ACCESS CONTROL CHECK
                  const senderAllowed = !acl || acl.isContactAllowed(senderPubkey);

                  if (senderAllowed) {
                    // Allowed sender — emit full message for OpenClaw
                    audit.logAllowedMessage({
                      senderPubkey,
                      groupId,
                      groupName,
                      contentPreview: content.slice(0, 100),
                    });

                    emit({
                      type: 'message',
                      timestamp: new Date().toISOString(),
                      groupId,
                      groupName,
                      senderPubkey,
                      content,
                      eventId: event.id,
                      allowed: true,
                    }, logFile);
                  } else {
                    // REJECTED — log metadata only, NO content, NO response
                    audit.logRejectedMessage({
                      senderPubkey,
                      groupId,
                      groupName,
                      reason: 'Sender not in allowlist',
                    });

                    // Emit redacted status (no content!)
                    emit({
                      type: 'message',
                      timestamp: new Date().toISOString(),
                      groupId,
                      groupName,
                      senderPubkey: senderPubkey.slice(0, 16) + '...',
                      content: '[REDACTED - sender not allowed]',
                      eventId: event.id,
                      allowed: false,
                    }, logFile);
                  }

                  // Always store message locally (for group state), but redact content if not allowed
                  store.saveMessage({
                    id: event.id,
                    groupId,
                    senderPubkey,
                    content: senderAllowed ? content : '[REDACTED]',
                    kind: innerEvent.kind,
                    createdAt: innerEvent.created_at,
                    tags: innerEvent.tags || [],
                  });

                  // Always update MLS state (required for protocol correctness)
                  const newEncoded = serializeGroupState(newState);
                  store.saveMlsState(groupId, newEncoded);
                }
              } catch (err: any) {
                // Don't spam logs with decrypt errors from non-MLS events
                if (!err.message.includes('invalid base64') &&
                    !err.message.includes('invalid payload length') &&
                    !err.message.includes('unknown encryption version')) {
                  emit({
                    type: 'status',
                    timestamp: new Date().toISOString(),
                    event: 'decrypt_error',
                    details: `${groupName}: ${err.message}`,
                  }, logFile);
                }
              }
            },
            () => {
              emit({
                type: 'status',
                timestamp: new Date().toISOString(),
                event: 'connected',
                details: `Listening on "${groupName}"`,
              }, logFile);
            },
          );

          // Keep alive until signal
          const onExit = () => {
            sub.close();
            pool.close();
            resolve();
          };
          process.once('SIGTERM', onExit);
          process.once('SIGINT', onExit);
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

  // Listen on all groups concurrently (ACL filtering happens inside listenToGroup)
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
