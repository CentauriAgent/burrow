/**
 * Access Control Layer for Burrow.
 * Allowlist-based authorization — only approved contacts/groups get responses.
 */

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export interface AccessControlConfig {
  version: number;
  owner: string; // hex pubkey — ONLY person who can modify permissions
  ownerNote?: string;
  allowedContacts: string[]; // hex pubkeys
  allowedGroups: string[]; // nostr group IDs
  defaultPolicy: 'ignore' | 'log'; // ignore = silent drop, log = log but don't respond
  updatedAt: string;
  updatedBy: string;
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

    this.config = JSON.parse(readFileSync(this.configPath, 'utf-8'));

    if (!this.config.owner || this.config.owner === 'DEREK_HEX_PUBKEY_REQUIRED') {
      throw new Error(
        'Owner pubkey not configured in access-control.json. ' +
        'Set the owner field to Derek\'s hex pubkey before running.'
      );
    }
  }

  /** Check if a sender pubkey is allowed to receive responses */
  isContactAllowed(pubkey: string): boolean {
    return pubkey === this.config.owner || this.config.allowedContacts.includes(pubkey);
  }

  /** Check if a group is allowed for participation */
  isGroupAllowed(groupId: string): boolean {
    return this.config.allowedGroups.includes(groupId);
  }

  /** Check if a pubkey is the owner */
  isOwner(pubkey: string): boolean {
    return pubkey === this.config.owner;
  }

  /** Get current config (read-only copy) */
  getConfig(): Readonly<AccessControlConfig> {
    return { ...this.config };
  }

  /**
   * Modify access control. ONLY callable by owner.
   * In daemon context, this is called after verifying the request came from owner.
   */
  modify(
    requesterPubkey: string,
    changes: {
      addContacts?: string[];
      removeContacts?: string[];
      addGroups?: string[];
      removeGroups?: string[];
    }
  ): { success: boolean; reason?: string } {
    if (!this.isOwner(requesterPubkey)) {
      return { success: false, reason: 'Only the owner can modify access control' };
    }

    if (changes.addContacts) {
      for (const c of changes.addContacts) {
        if (!this.config.allowedContacts.includes(c)) {
          this.config.allowedContacts.push(c);
        }
      }
    }

    if (changes.removeContacts) {
      this.config.allowedContacts = this.config.allowedContacts.filter(
        c => !changes.removeContacts!.includes(c)
      );
    }

    if (changes.addGroups) {
      for (const g of changes.addGroups) {
        if (!this.config.allowedGroups.includes(g)) {
          this.config.allowedGroups.push(g);
        }
      }
    }

    if (changes.removeGroups) {
      this.config.allowedGroups = this.config.allowedGroups.filter(
        g => !changes.removeGroups!.includes(g)
      );
    }

    this.config.updatedAt = new Date().toISOString();
    this.config.updatedBy = requesterPubkey.slice(0, 16);
    this.save();

    return { success: true };
  }

  private save(): void {
    writeFileSync(this.configPath, JSON.stringify(this.config, null, 2), { mode: 0o600 });
  }
}
