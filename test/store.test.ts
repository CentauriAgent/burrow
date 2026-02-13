import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { BurrowStore } from '../src/store/index.js';
import { mkdtempSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import type { StoredGroup, StoredKeyPackage, GroupMessage } from '../src/types/index.js';

describe('BurrowStore', () => {
  let tempDir: string;
  let store: BurrowStore;

  beforeEach(() => {
    tempDir = mkdtempSync(join(tmpdir(), 'burrow-store-'));
    store = new BurrowStore(tempDir);
  });

  afterEach(() => {
    rmSync(tempDir, { recursive: true, force: true });
  });

  // --- Groups ---
  describe('Groups', () => {
    const group: StoredGroup = {
      mlsGroupId: 'aa'.repeat(32),
      nostrGroupId: 'bb'.repeat(32),
      name: 'Test Group',
      description: 'desc',
      adminPubkeys: ['cc'.repeat(32)],
      relays: ['wss://r.test'],
      mlsState: 'base64state',
      createdAt: 1000,
      lastMessageAt: 2000,
      epoch: 0,
    };

    it('should save and retrieve a group', () => {
      store.saveGroup(group);
      const loaded = store.getGroup(group.nostrGroupId);
      expect(loaded).toEqual(group);
    });

    it('should return null for missing group', () => {
      expect(store.getGroup('nonexistent')).toBeNull();
    });

    it('should list groups', () => {
      store.saveGroup(group);
      store.saveGroup({ ...group, nostrGroupId: 'dd'.repeat(32), name: 'Group 2' });
      const groups = store.listGroups();
      expect(groups.length).toBe(2);
    });

    it('should overwrite group on save', () => {
      store.saveGroup(group);
      store.saveGroup({ ...group, name: 'Updated' });
      const loaded = store.getGroup(group.nostrGroupId);
      expect(loaded?.name).toBe('Updated');
    });
  });

  // --- MLS State ---
  describe('MLS State (binary)', () => {
    it('should save and retrieve binary state', () => {
      const state = new Uint8Array([1, 2, 3, 4, 5]);
      store.saveMlsState('group1', state);
      const loaded = store.getMlsState('group1');
      expect(loaded).toEqual(state);
    });

    it('should return null for missing state', () => {
      expect(store.getMlsState('missing')).toBeNull();
    });
  });

  // --- Key Packages ---
  describe('Key Packages', () => {
    const kp: StoredKeyPackage = {
      id: 'kp1',
      mlsKeyPackage: 'base64kp',
      privateKey: 'base64priv',
      createdAt: 1000,
      isLastResort: true,
    };

    it('should save and retrieve key package', () => {
      store.saveKeyPackage(kp);
      expect(store.getKeyPackage('kp1')).toEqual(kp);
    });

    it('should list key packages', () => {
      store.saveKeyPackage(kp);
      store.saveKeyPackage({ ...kp, id: 'kp2' });
      expect(store.listKeyPackages().length).toBe(2);
    });

    it('should delete key package', () => {
      store.saveKeyPackage(kp);
      store.deleteKeyPackage('kp1');
      expect(store.getKeyPackage('kp1')).toBeNull();
    });

    it('should not throw when deleting nonexistent', () => {
      expect(() => store.deleteKeyPackage('nope')).not.toThrow();
    });
  });

  // --- Messages ---
  describe('Messages', () => {
    const msg: GroupMessage = {
      id: 'msg1',
      groupId: 'grp1',
      senderPubkey: 'aa'.repeat(32),
      content: 'Hello!',
      kind: 9,
      createdAt: 1000,
      tags: [],
    };

    it('should save and retrieve messages', () => {
      store.saveMessage(msg);
      const msgs = store.getMessages('grp1');
      expect(msgs.length).toBe(1);
      expect(msgs[0].content).toBe('Hello!');
    });

    it('should return empty for no messages', () => {
      expect(store.getMessages('empty')).toEqual([]);
    });

    it('should respect limit', () => {
      for (let i = 0; i < 10; i++) {
        store.saveMessage({ ...msg, id: `msg${i}`, createdAt: 1000 + i });
      }
      const msgs = store.getMessages('grp1', 3);
      expect(msgs.length).toBe(3);
    });

    it('should sort by created_at', () => {
      store.saveMessage({ ...msg, id: 'old', createdAt: 100 });
      store.saveMessage({ ...msg, id: 'new', createdAt: 200 });
      const msgs = store.getMessages('grp1');
      expect(msgs[0].createdAt).toBeLessThanOrEqual(msgs[1].createdAt);
    });
  });
});
