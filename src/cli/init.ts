/**
 * `burrow init` — Initialize Burrow identity and publish a KeyPackage.
 */

import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { loadIdentity, generateIdentity } from '../crypto/index.js';
import { generateMarmotKeyPackage } from '../mls/index.js';
import { RelayPool, buildKeyPackageEvent } from '../nostr/index.js';
import { BurrowStore } from '../store/index.js';
import { DEFAULT_RELAYS } from '../types/index.js';
import { bytesToHex } from '@noble/hashes/utils.js';

export async function initCommand(opts: {
  keyPath?: string;
  dataDir?: string;
  relays?: string[];
  generate?: boolean;
}): Promise<void> {
  const dataDir = opts.dataDir || join(process.env.HOME || '~', '.burrow');
  const relays = opts.relays || DEFAULT_RELAYS;

  console.log('🦫 Initializing Burrow...\n');

  // 1. Load or generate identity
  let identity;
  try {
    identity = loadIdentity(opts.keyPath);
    console.log(`✅ Loaded identity: ${identity.publicKeyHex.slice(0, 16)}...`);
  } catch {
    if (opts.generate) {
      identity = generateIdentity(opts.keyPath);
      console.log(`🔑 Generated new identity: ${identity.publicKeyHex.slice(0, 16)}...`);
    } else {
      console.error('❌ No secret key found. Use --generate to create one, or ensure ~/.clawstr/secret.key exists.');
      process.exit(1);
    }
  }

  // 2. Initialize store
  const store = new BurrowStore(dataDir);
  console.log(`📁 Data directory: ${dataDir}`);

  // 3. Generate KeyPackage
  console.log('\n🔐 Generating MLS KeyPackage...');
  const kp = await generateMarmotKeyPackage(identity);
  console.log(`  KeyPackage generated (${kp.serializedBase64.length} bytes base64)`);

  // 4. Publish KeyPackage to relays
  console.log(`\n📡 Publishing KeyPackage to ${relays.length} relays...`);
  const event = buildKeyPackageEvent(identity, kp.serializedBase64, {
    relays,
    client: 'Burrow/0.1.0',
  });

  const pool = new RelayPool(relays);
  try {
    await pool.publish(event);
    console.log(`  Event ID: ${event.id}`);
  } finally {
    pool.close();
  }

  // 5. Store the key package locally
  store.saveKeyPackage({
    id: event.id,
    mlsKeyPackage: kp.serializedBase64,
    privateKey: Buffer.from(kp.serialized).toString('base64'), // store full serialized for now
    createdAt: event.created_at,
    isLastResort: true,
  });

  // 6. Generate access-control.json if it doesn't exist
  const aclPath = join(dataDir, 'access-control.json');
  if (!existsSync(aclPath)) {
    const ownerHex = process.env.BURROW_OWNER_HEX || '';
    const ownerNpub = process.env.BURROW_OWNER_NPUB || '';

    if (ownerHex || ownerNpub) {
      let resolvedHex = ownerHex;
      if (!resolvedHex && ownerNpub) {
        try {
          const { execSync } = require('node:child_process');
          resolvedHex = execSync(`nak decode ${ownerNpub} 2>/dev/null`, { encoding: 'utf-8' }).trim();
        } catch { /* user will need to set manually */ }
      }
      const acl = {
        version: 1,
        owner: {
          npub: ownerNpub,
          hex: resolvedHex,
          note: 'Set from environment variables during init',
        },
        defaultPolicy: 'ignore',
        allowedContacts: [],
        allowedGroups: [],
        settings: { logRejectedContent: false, auditEnabled: true },
      };
      writeFileSync(aclPath, JSON.stringify(acl, null, 2) + '\n', { mode: 0o600 });
      console.log('\n🔐 Access control initialized from BURROW_OWNER_HEX/BURROW_OWNER_NPUB');
    } else {
      const acl = {
        version: 1,
        owner: { npub: '', hex: '', note: 'Set BURROW_OWNER_HEX or edit this file' },
        defaultPolicy: 'ignore',
        allowedContacts: [],
        allowedGroups: [],
        settings: { logRejectedContent: false, auditEnabled: true },
      };
      writeFileSync(aclPath, JSON.stringify(acl, null, 2) + '\n', { mode: 0o600 });
      console.log('\n⚠️  Access control created but NO OWNER SET.');
      console.log('   Set BURROW_OWNER_HEX env var or edit ~/.burrow/access-control.json');
    }
  }

  console.log('\n✅ Burrow initialized! Your KeyPackage is published.');
  console.log(`   Public key: ${identity.publicKeyHex}`);
  console.log(`   KeyPackage event: ${event.id}`);
}
