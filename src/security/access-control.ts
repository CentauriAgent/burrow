/**
 * Access Control Layer for Burrow.
 * Allowlist-based authorization — only approved contacts/groups get responses.
 */

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

export interface OwnerConfig {
  npub: string;
  hex: string;
  note?: string;
}

export interface AccessControlConfig {
  version: number;
  owner: OwnerConfig;
  defaultPolicy: 'ignore' | 'log';
  allowedContacts: string[]; // hex pubkeys
  allowedGroups: string[]; // nostr group IDs
  settings: {
    logRejectedContent: boolean;
    auditEnabled: boolean;
  };
}

export class AccessControl {
  private configPath: string;
  private config: AccessControlConfig;

  constructor(dataDir: string) {
    this.configPath = join(dataDir, 'access-control.json');

    if (!existsSync(this.configPath)) {
      throw new Error(
        'access-control.json not found. Run setup first. ' +
        'Burrow WILL NOT operate without access control.'
      );
    }

    const raw = JSON.parse(readFileSync(this.configPath, 'utf-8'));

    // Handle both old (owner: string) and new (owner: {hex, npub}) formats
    if (typeof raw.owner === 'string') {
      raw.owner = { hex: raw.owner, npub: '', note: 'Migrated from legacy format' };
    }

    this.config = raw as AccessControlConfig;

    // Ensure settings exist
    if (!this.config.settings) {
      this.config.settings = { logRejectedContent: false, auditEnabled: true };
    }

    const ownerHex = this.config.owner?.hex;
    if (!ownerHex || ownerHex === 'DEREK_HEX_PUBKEY_REQUIRED') {
      throw new Error(
        'Owner pubkey not configured in access-control.json. ' +
        'Set the owner.hex field before running.'
      );
    }
  }

  /** The owner's hex pubkey */
  get ownerHex(): string {
    return this.config.owner.hex;
  }

  /** Check if a sender pubkey is allowed to receive responses */
  isContactAllowed(pubkey: string): boolean {
    return pubkey === this.config.owner.hex || this.config.allowedContacts.includes(pubkey);
  }

  /** Check if a group is allowed for participation */
  isGroupAllowed(groupId: string): boolean {
    return this.config.allowedGroups.includes(groupId);
  }

  /** Check if a pubkey is the owner */
  isOwner(pubkey: string): boolean {
    return pubkey === this.config.owner.hex;
  }

  /** Get current config (read-only copy) */
  getConfig(): Readonly<AccessControlConfig> {
    return JSON.parse(JSON.stringify(this.config));
  }

  /**
   * Add a contact to the allowlist.
   * In CLI context (local), no owner check needed.
   * In daemon context, verify requester is owner first.
   */
  addContact(hexPubkey: string): void {
    if (!this.config.allowedContacts.includes(hexPubkey)) {
      this.config.allowedContacts.push(hexPubkey);
      this.save();
    }
  }

  /** Remove a contact from the allowlist */
  removeContact(hexPubkey: string): boolean {
    const before = this.config.allowedContacts.length;
    this.config.allowedContacts = this.config.allowedContacts.filter(c => c !== hexPubkey);
    if (this.config.allowedContacts.length !== before) {
      this.save();
      return true;
    }
    return false;
  }

  /** Add a group to the allowlist */
  addGroup(groupId: string): void {
    if (!this.config.allowedGroups.includes(groupId)) {
      this.config.allowedGroups.push(groupId);
      this.save();
    }
  }

  /** Remove a group from the allowlist */
  removeGroup(groupId: string): boolean {
    const before = this.config.allowedGroups.length;
    this.config.allowedGroups = this.config.allowedGroups.filter(g => g !== groupId);
    if (this.config.allowedGroups.length !== before) {
      this.save();
      return true;
    }
    return false;
  }

  private save(): void {
    writeFileSync(this.configPath, JSON.stringify(this.config, null, 2) + '\n', { mode: 0o600 });
  }

  /** Read audit log entries for the last N days */
  static readAuditLog(dataDir: string, days: number = 7): string[] {
    const auditDir = join(dataDir, 'audit');
    if (!existsSync(auditDir)) return [];

    const now = Date.now();
    const cutoff = now - days * 86400000;
    const files = readdirSync(auditDir)
      .filter(f => f.endsWith('.jsonl'))
      .sort()
      .filter(f => {
        const dateStr = f.replace('.jsonl', '');
        return new Date(dateStr).getTime() >= cutoff;
      });

    const lines: string[] = [];
    for (const file of files) {
      const content = readFileSync(join(auditDir, file), 'utf-8').trim();
      if (content) lines.push(...content.split('\n'));
    }
    return lines;
  }
}
