import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { AccessControl } from '../src/security/access-control.js';
import { AuditLog } from '../src/security/audit.js';

const OWNER_HEX = '3f770d65d3a764a9c5cb503ae123e62ec7598ad035d836e2a810f3877a745b24';
const ALLOWED_CONTACT = 'aaaa000000000000000000000000000000000000000000000000000000000001';
const UNKNOWN_CONTACT = 'bbbb000000000000000000000000000000000000000000000000000000000002';
const ALLOWED_GROUP = 'e93f729711a7b0bc11d1ccf347f58cf96ea6937fe2cbf4e433e8589f1b9031c7';
const UNKNOWN_GROUP = 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

function makeConfig(overrides: any = {}) {
  return {
    version: 1,
    owner: { npub: 'npub1test', hex: OWNER_HEX, note: 'test' },
    defaultPolicy: 'ignore',
    allowedContacts: [ALLOWED_CONTACT],
    allowedGroups: [ALLOWED_GROUP],
    settings: { logRejectedContent: false, auditEnabled: true },
    ...overrides,
  };
}

describe('AccessControl', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'burrow-test-'));
    writeFileSync(join(tmpDir, 'access-control.json'), JSON.stringify(makeConfig()));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('throws if config file missing', () => {
    const emptyDir = mkdtempSync(join(tmpdir(), 'burrow-empty-'));
    expect(() => new AccessControl(emptyDir)).toThrow('not found');
    rmSync(emptyDir, { recursive: true, force: true });
  });

  it('throws if owner not set', () => {
    writeFileSync(
      join(tmpDir, 'access-control.json'),
      JSON.stringify(makeConfig({ owner: { hex: 'DEREK_HEX_PUBKEY_REQUIRED', npub: '' } }))
    );
    expect(() => new AccessControl(tmpDir)).toThrow('Owner pubkey not configured');
  });

  it('allows owner contact', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isContactAllowed(OWNER_HEX)).toBe(true);
  });

  it('allows listed contact', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isContactAllowed(ALLOWED_CONTACT)).toBe(true);
  });

  it('rejects unknown contact', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isContactAllowed(UNKNOWN_CONTACT)).toBe(false);
  });

  it('allows listed group', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isGroupAllowed(ALLOWED_GROUP)).toBe(true);
  });

  it('rejects unknown group', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isGroupAllowed(UNKNOWN_GROUP)).toBe(false);
  });

  it('isOwner works correctly', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.isOwner(OWNER_HEX)).toBe(true);
    expect(acl.isOwner(ALLOWED_CONTACT)).toBe(false);
  });

  it('add-contact persists', () => {
    const acl = new AccessControl(tmpDir);
    acl.addContact(UNKNOWN_CONTACT);
    expect(acl.isContactAllowed(UNKNOWN_CONTACT)).toBe(true);
    // Reload and verify persistence
    const acl2 = new AccessControl(tmpDir);
    expect(acl2.isContactAllowed(UNKNOWN_CONTACT)).toBe(true);
  });

  it('remove-contact works', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.removeContact(ALLOWED_CONTACT)).toBe(true);
    expect(acl.isContactAllowed(ALLOWED_CONTACT)).toBe(false);
    // Removing non-existent returns false
    expect(acl.removeContact('nonexistent')).toBe(false);
  });

  it('add-group persists', () => {
    const acl = new AccessControl(tmpDir);
    acl.addGroup(UNKNOWN_GROUP);
    expect(acl.isGroupAllowed(UNKNOWN_GROUP)).toBe(true);
    const acl2 = new AccessControl(tmpDir);
    expect(acl2.isGroupAllowed(UNKNOWN_GROUP)).toBe(true);
  });

  it('remove-group works', () => {
    const acl = new AccessControl(tmpDir);
    expect(acl.removeGroup(ALLOWED_GROUP)).toBe(true);
    expect(acl.isGroupAllowed(ALLOWED_GROUP)).toBe(false);
  });

  it('handles legacy string owner format', () => {
    writeFileSync(
      join(tmpDir, 'access-control.json'),
      JSON.stringify({
        version: 1,
        owner: OWNER_HEX,
        allowedContacts: [],
        allowedGroups: [],
        defaultPolicy: 'ignore',
      })
    );
    const acl = new AccessControl(tmpDir);
    expect(acl.isOwner(OWNER_HEX)).toBe(true);
  });

  it('does not duplicate on double-add', () => {
    const acl = new AccessControl(tmpDir);
    acl.addContact(ALLOWED_CONTACT);
    acl.addContact(ALLOWED_CONTACT);
    expect(acl.getConfig().allowedContacts.filter(c => c === ALLOWED_CONTACT).length).toBe(1);
  });
});

describe('AuditLog', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'burrow-audit-'));
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('creates audit directory', () => {
    new AuditLog(tmpDir);
    expect(existsSync(join(tmpDir, 'audit'))).toBe(true);
  });

  it('logs allowed message with content preview', () => {
    const audit = new AuditLog(tmpDir);
    audit.logAllowedMessage({
      senderPubkey: ALLOWED_CONTACT,
      groupId: ALLOWED_GROUP,
      groupName: 'Test Group',
      contentPreview: 'Hello world',
    });
    const date = new Date().toISOString().slice(0, 10);
    const logFile = join(tmpDir, 'audit', `${date}.jsonl`);
    expect(existsSync(logFile)).toBe(true);
    const entry = JSON.parse(readFileSync(logFile, 'utf-8').trim());
    expect(entry.type).toBe('message_received');
    expect(entry.allowed).toBe(true);
    expect(entry.senderPubkey).toBe(ALLOWED_CONTACT);
    expect(entry.details).toBe('Hello world');
  });

  it('logs rejected message without content, truncated pubkey', () => {
    const audit = new AuditLog(tmpDir);
    audit.logRejectedMessage({
      senderPubkey: UNKNOWN_CONTACT,
      groupId: ALLOWED_GROUP,
      groupName: 'Test Group',
      reason: 'Sender not in allowlist',
    });
    const date = new Date().toISOString().slice(0, 10);
    const logFile = join(tmpDir, 'audit', `${date}.jsonl`);
    const entry = JSON.parse(readFileSync(logFile, 'utf-8').trim());
    expect(entry.type).toBe('message_rejected');
    expect(entry.allowed).toBe(false);
    expect(entry.senderPubkey).toBe(UNKNOWN_CONTACT.slice(0, 16) + '...');
    expect(entry.details).toBe('Sender not in allowlist');
    // Content must NOT be present
    expect(entry.content).toBeUndefined();
  });

  it('logs access changes', () => {
    const audit = new AuditLog(tmpDir);
    audit.logAccessChange({
      requesterPubkey: 'cli-local',
      allowed: true,
      details: 'Added contact: test',
    });
    const date = new Date().toISOString().slice(0, 10);
    const logFile = join(tmpDir, 'audit', `${date}.jsonl`);
    const entry = JSON.parse(readFileSync(logFile, 'utf-8').trim());
    expect(entry.type).toBe('access_change');
  });
});

describe('AccessControl.readAuditLog', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'burrow-readaudit-'));
    mkdirSync(join(tmpDir, 'audit'), { recursive: true });
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('reads entries from today', () => {
    const date = new Date().toISOString().slice(0, 10);
    writeFileSync(
      join(tmpDir, 'audit', `${date}.jsonl`),
      '{"type":"test","timestamp":"2026-02-13T00:00:00Z"}\n'
    );
    const lines = AccessControl.readAuditLog(tmpDir, 1);
    expect(lines.length).toBe(1);
  });

  it('returns empty for no audit dir', () => {
    const emptyDir = mkdtempSync(join(tmpdir(), 'burrow-noaudit-'));
    const lines = AccessControl.readAuditLog(emptyDir, 7);
    expect(lines.length).toBe(0);
    rmSync(emptyDir, { recursive: true, force: true });
  });
});
