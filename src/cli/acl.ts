/**
 * `burrow acl` — Access control management commands.
 */

import { join } from 'node:path';
import { AccessControl } from '../security/index.js';
import { AuditLog } from '../security/index.js';

function getDataDir(opts: { dataDir?: string }): string {
  return opts.dataDir || join(process.env.HOME || '~', '.burrow');
}

/** Convert npub to hex if needed (basic bech32 decode) */
function resolveToHex(input: string): string {
  // If already hex (64 chars), return as-is
  if (/^[0-9a-f]{64}$/i.test(input)) return input.toLowerCase();
  // npub → need nak decode or manual bech32
  // For now, require hex or shell out to nak
  if (input.startsWith('npub1')) {
    try {
      const { execSync } = require('node:child_process');
      const hex = execSync(`nak decode ${input} 2>/dev/null`, { encoding: 'utf-8' }).trim();
      if (/^[0-9a-f]{64}$/i.test(hex)) return hex;
    } catch {
      // fall through
    }
    console.error(`❌ Could not decode npub. Provide hex pubkey or install 'nak'.`);
    process.exit(1);
  }
  return input;
}

export function aclShowCommand(opts: { dataDir?: string }): void {
  const dataDir = getDataDir(opts);
  try {
    const acl = new AccessControl(dataDir);
    const config = acl.getConfig();
    console.log('🔐 Burrow Access Control');
    console.log('========================');
    console.log(`Owner: ${config.owner.npub || config.owner.hex}`);
    console.log(`       ${config.owner.hex}`);
    console.log(`Policy: ${config.defaultPolicy}`);
    console.log(`\nAllowed Contacts (${config.allowedContacts.length}):`);
    if (config.allowedContacts.length === 0) {
      console.log('  (none — only owner can send messages)');
    } else {
      for (const c of config.allowedContacts) {
        console.log(`  • ${c}`);
      }
    }
    console.log(`\nAllowed Groups (${config.allowedGroups.length}):`);
    if (config.allowedGroups.length === 0) {
      console.log('  (none)');
    } else {
      for (const g of config.allowedGroups) {
        console.log(`  • ${g}`);
      }
    }
    console.log(`\nSettings:`);
    console.log(`  Log rejected content: ${config.settings.logRejectedContent}`);
    console.log(`  Audit enabled: ${config.settings.auditEnabled}`);
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

export function aclAddContactCommand(pubkeyOrNpub: string, opts: { dataDir?: string }): void {
  const dataDir = getDataDir(opts);
  const hex = resolveToHex(pubkeyOrNpub);
  try {
    const acl = new AccessControl(dataDir);
    acl.addContact(hex);
    const audit = new AuditLog(dataDir);
    audit.logAccessChange({
      requesterPubkey: 'cli-local',
      allowed: true,
      details: `Added contact: ${hex}`,
    });
    console.log(`✅ Added contact: ${hex}`);
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

export function aclRemoveContactCommand(pubkeyOrNpub: string, opts: { dataDir?: string }): void {
  const dataDir = getDataDir(opts);
  const hex = resolveToHex(pubkeyOrNpub);
  try {
    const acl = new AccessControl(dataDir);
    const removed = acl.removeContact(hex);
    if (removed) {
      const audit = new AuditLog(dataDir);
      audit.logAccessChange({
        requesterPubkey: 'cli-local',
        allowed: true,
        details: `Removed contact: ${hex}`,
      });
      console.log(`✅ Removed contact: ${hex}`);
    } else {
      console.log(`⚠️ Contact not found: ${hex}`);
    }
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

export function aclAddGroupCommand(groupId: string, opts: { dataDir?: string }): void {
  const dataDir = getDataDir(opts);
  try {
    const acl = new AccessControl(dataDir);
    acl.addGroup(groupId);
    const audit = new AuditLog(dataDir);
    audit.logAccessChange({
      requesterPubkey: 'cli-local',
      allowed: true,
      details: `Added group: ${groupId}`,
    });
    console.log(`✅ Added group: ${groupId}`);
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

export function aclRemoveGroupCommand(groupId: string, opts: { dataDir?: string }): void {
  const dataDir = getDataDir(opts);
  try {
    const acl = new AccessControl(dataDir);
    const removed = acl.removeGroup(groupId);
    if (removed) {
      const audit = new AuditLog(dataDir);
      audit.logAccessChange({
        requesterPubkey: 'cli-local',
        allowed: true,
        details: `Removed group: ${groupId}`,
      });
      console.log(`✅ Removed group: ${groupId}`);
    } else {
      console.log(`⚠️ Group not found: ${groupId}`);
    }
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}

export function aclAuditCommand(opts: { dataDir?: string; days?: string }): void {
  const dataDir = getDataDir(opts);
  const days = parseInt(opts.days || '7');
  try {
    const lines = AccessControl.readAuditLog(dataDir, days);
    if (lines.length === 0) {
      console.log(`No audit entries in the last ${days} day(s).`);
      return;
    }
    console.log(`📋 Audit log (last ${days} day(s), ${lines.length} entries):`);
    console.log('─'.repeat(80));
    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        const time = entry.timestamp?.slice(11, 19) || '??:??:??';
        const date = entry.timestamp?.slice(0, 10) || '????-??-??';
        const icon = entry.allowed ? '✅' : '🚫';
        const sender = entry.senderPubkey ? ` from:${entry.senderPubkey.slice(0, 12)}..` : '';
        const group = entry.groupId ? ` group:${entry.groupId.slice(0, 12)}..` : '';
        console.log(`${icon} ${date} ${time} [${entry.type}]${sender}${group} ${entry.details || ''}`);
      } catch {
        console.log(line);
      }
    }
  } catch (err: any) {
    console.error(`❌ ${err.message}`);
    process.exit(1);
  }
}
