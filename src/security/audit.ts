/**
 * Audit trail for Burrow.
 * Logs all message activity with daily rotation.
 */

import { appendFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

export type AuditEventType =
  | 'message_received'    // From allowed contact
  | 'message_rejected'    // From unknown/disallowed sender
  | 'message_sent'        // Outgoing message
  | 'group_rejected'      // Message in disallowed group
  | 'access_change'       // Permission modification
  | 'daemon_start'        // Daemon started
  | 'daemon_stop'         // Daemon stopped
  | 'error';              // Security-relevant error

export interface AuditEntry {
  timestamp: string;
  type: AuditEventType;
  senderPubkey?: string;  // hex, truncated for rejected
  groupId?: string;
  groupName?: string;
  allowed: boolean;
  details?: string;
  // NEVER include decrypted content from rejected senders
}

export class AuditLog {
  private auditDir: string;

  constructor(dataDir: string) {
    this.auditDir = join(dataDir, 'audit');
    mkdirSync(this.auditDir, { recursive: true });
  }

  log(entry: AuditEntry): void {
    const date = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
    const path = join(this.auditDir, `${date}.jsonl`);
    appendFileSync(path, JSON.stringify(entry) + '\n', { mode: 0o600 });
  }

  /** Log an allowed incoming message (includes content summary) */
  logAllowedMessage(opts: {
    senderPubkey: string;
    groupId: string;
    groupName: string;
    contentPreview?: string; // first 100 chars max
  }): void {
    this.log({
      timestamp: new Date().toISOString(),
      type: 'message_received',
      senderPubkey: opts.senderPubkey,
      groupId: opts.groupId,
      groupName: opts.groupName,
      allowed: true,
      details: opts.contentPreview?.slice(0, 100),
    });
  }

  /** Log a rejected message — NO content, truncated pubkey */
  logRejectedMessage(opts: {
    senderPubkey: string;
    groupId: string;
    groupName: string;
    reason: string;
  }): void {
    this.log({
      timestamp: new Date().toISOString(),
      type: 'message_rejected',
      senderPubkey: opts.senderPubkey.slice(0, 16) + '...',
      groupId: opts.groupId,
      groupName: opts.groupName,
      allowed: false,
      details: opts.reason,
    });
  }

  /** Log outgoing message */
  logSentMessage(opts: {
    groupId: string;
    groupName: string;
    contentPreview?: string;
  }): void {
    this.log({
      timestamp: new Date().toISOString(),
      type: 'message_sent',
      groupId: opts.groupId,
      groupName: opts.groupName,
      allowed: true,
      details: opts.contentPreview?.slice(0, 100),
    });
  }

  /** Log access control change */
  logAccessChange(opts: {
    requesterPubkey: string;
    allowed: boolean;
    details: string;
  }): void {
    this.log({
      timestamp: new Date().toISOString(),
      type: 'access_change',
      senderPubkey: opts.requesterPubkey,
      allowed: opts.allowed,
      details: opts.details,
    });
  }
}
