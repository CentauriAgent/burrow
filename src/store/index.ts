/**
 * Simple file-based storage for Burrow state.
 * Stores groups, key packages, and messages as JSON files.
 */

import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import type { StoredGroup, StoredKeyPackage, GroupMessage } from '../types/index.js';

export class BurrowStore {
  private baseDir: string;

  constructor(dataDir: string) {
    this.baseDir = dataDir;
    mkdirSync(join(this.baseDir, 'groups'), { recursive: true });
    mkdirSync(join(this.baseDir, 'keypackages'), { recursive: true });
    mkdirSync(join(this.baseDir, 'messages'), { recursive: true });
    mkdirSync(join(this.baseDir, 'mls-state'), { recursive: true });
  }

  // --- Groups ---
  saveGroup(group: StoredGroup): void {
    const path = join(this.baseDir, 'groups', `${group.nostrGroupId}.json`);
    writeFileSync(path, JSON.stringify(group, null, 2));
  }

  getGroup(nostrGroupId: string): StoredGroup | null {
    const path = join(this.baseDir, 'groups', `${nostrGroupId}.json`);
    if (!existsSync(path)) return null;
    return JSON.parse(readFileSync(path, 'utf-8'));
  }

  listGroups(): StoredGroup[] {
    const dir = join(this.baseDir, 'groups');
    if (!existsSync(dir)) return [];
    return readdirSync(dir)
      .filter(f => f.endsWith('.json'))
      .map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
  }

  // --- MLS State (binary) ---
  saveMlsState(groupId: string, state: Uint8Array): void {
    const path = join(this.baseDir, 'mls-state', `${groupId}.bin`);
    writeFileSync(path, Buffer.from(state));
  }

  getMlsState(groupId: string): Uint8Array | null {
    const path = join(this.baseDir, 'mls-state', `${groupId}.bin`);
    if (!existsSync(path)) return null;
    return new Uint8Array(readFileSync(path));
  }

  // --- Key Packages ---
  saveKeyPackage(kp: StoredKeyPackage): void {
    const path = join(this.baseDir, 'keypackages', `${kp.id}.json`);
    writeFileSync(path, JSON.stringify(kp, null, 2));
  }

  getKeyPackage(id: string): StoredKeyPackage | null {
    const path = join(this.baseDir, 'keypackages', `${id}.json`);
    if (!existsSync(path)) return null;
    return JSON.parse(readFileSync(path, 'utf-8'));
  }

  listKeyPackages(): StoredKeyPackage[] {
    const dir = join(this.baseDir, 'keypackages');
    if (!existsSync(dir)) return [];
    return readdirSync(dir)
      .filter(f => f.endsWith('.json'))
      .map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
  }

  deleteKeyPackage(id: string): void {
    const path = join(this.baseDir, 'keypackages', `${id}.json`);
    if (existsSync(path)) {
      const { unlinkSync } = require('node:fs');
      unlinkSync(path);
    }
  }

  // --- Messages ---
  saveMessage(msg: GroupMessage): void {
    const dir = join(this.baseDir, 'messages', msg.groupId);
    mkdirSync(dir, { recursive: true });
    const path = join(dir, `${msg.createdAt}-${msg.id.slice(0, 8)}.json`);
    writeFileSync(path, JSON.stringify(msg, null, 2));
  }

  getMessages(groupId: string, limit = 50): GroupMessage[] {
    const dir = join(this.baseDir, 'messages', groupId);
    if (!existsSync(dir)) return [];
    const files = readdirSync(dir)
      .filter(f => f.endsWith('.json'))
      .sort()
      .slice(-limit);
    return files.map(f => JSON.parse(readFileSync(join(dir, f), 'utf-8')));
  }
}
