/**
 * `burrow create-group` — Create a new encrypted group.
 * `burrow groups` — List groups.
 */

import { join } from 'node:path';
import { loadIdentity } from '../crypto/index.js';
import { createMarmotGroup, serializeGroupState } from '../mls/index.js';
import { BurrowStore } from '../store/index.js';
import { DEFAULT_RELAYS } from '../types/index.js';
import { bytesToHex } from '@noble/hashes/utils.js';

export async function createGroupCommand(opts: {
  name: string;
  description?: string;
  keyPath?: string;
  dataDir?: string;
  relays?: string[];
}): Promise<void> {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const relays = opts.relays || DEFAULT_RELAYS;

  console.log(`🦫 Creating group "${opts.name}"...\n`);

  const identity = loadIdentity(opts.keyPath);
  const store = new BurrowStore(dataDir);

  const { group, encodedState } = await createMarmotGroup(identity, {
    name: opts.name,
    description: opts.description,
    relays,
  });

  const nostrGroupIdHex = bytesToHex(group.nostrGroupId);

  // Store MLS state
  store.saveMlsState(nostrGroupIdHex, encodedState);

  // Store group metadata
  store.saveGroup({
    mlsGroupId: bytesToHex(new Uint8Array(32)), // placeholder - extracted from state
    nostrGroupId: nostrGroupIdHex,
    name: opts.name,
    description: opts.description || '',
    adminPubkeys: [identity.publicKeyHex],
    relays,
    mlsState: Buffer.from(encodedState).toString('base64'),
    createdAt: Math.floor(Date.now() / 1000),
    lastMessageAt: 0,
    epoch: 0,
  });

  console.log(`✅ Group created!`);
  console.log(`   Name: ${opts.name}`);
  console.log(`   Group ID: ${nostrGroupIdHex.slice(0, 16)}...`);
  console.log(`   Admin: ${identity.publicKeyHex.slice(0, 16)}...`);
  console.log(`   Relays: ${relays.join(', ')}`);
  console.log(`\n   Use 'burrow invite <pubkey>' to add members.`);
}

export function listGroupsCommand(opts: {
  dataDir?: string;
}): void {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const store = new BurrowStore(dataDir);
  const groups = store.listGroups();

  if (groups.length === 0) {
    console.log('No groups found. Create one with: burrow create-group "My Group"');
    return;
  }

  console.log(`🦫 Groups (${groups.length}):\n`);
  for (const g of groups) {
    const age = Math.floor(Date.now() / 1000) - g.createdAt;
    const ageStr = age < 3600
      ? `${Math.floor(age / 60)}m ago`
      : age < 86400
        ? `${Math.floor(age / 3600)}h ago`
        : `${Math.floor(age / 86400)}d ago`;
    console.log(`  📬 ${g.name}`);
    console.log(`     ID: ${g.nostrGroupId.slice(0, 16)}...`);
    console.log(`     Created: ${ageStr} | Epoch: ${g.epoch}`);
    console.log();
  }
}
