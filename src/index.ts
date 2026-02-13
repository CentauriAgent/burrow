#!/usr/bin/env node
/**
 * Burrow — Marmot Protocol (MLS + Nostr) encrypted messaging CLI.
 * 🦫 Signal-level E2EE without phone numbers.
 */

import { Command } from 'commander';
import {
  initCommand,
  createGroupCommand,
  listGroupsCommand,
  inviteCommand,
  sendCommand,
  readCommand,
  listenCommand,
  daemonCommand,
} from './cli/index.js';

const program = new Command();

program
  .name('burrow')
  .description('🦫 Marmot Protocol encrypted messaging for AI agents and humans')
  .version('0.1.0');

// --- burrow init ---
program
  .command('init')
  .description('Initialize Burrow identity and publish a KeyPackage')
  .option('-k, --key-path <path>', 'Path to Nostr secret key', undefined)
  .option('-d, --data-dir <path>', 'Data directory', undefined)
  .option('-r, --relay <url...>', 'Relay URLs')
  .option('-g, --generate', 'Generate a new identity if none exists')
  .action(async (opts) => {
    await initCommand({
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
      relays: opts.relay,
      generate: opts.generate,
    });
  });

// --- burrow create-group ---
program
  .command('create-group')
  .description('Create a new encrypted group')
  .argument('<name>', 'Group name')
  .option('--description <text>', 'Group description')
  .option('-k, --key-path <path>', 'Path to Nostr secret key')
  .option('-d, --data-dir <path>', 'Data directory')
  .option('-r, --relay <url...>', 'Relay URLs')
  .action(async (name, opts) => {
    await createGroupCommand({
      name,
      description: opts.description,
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
      relays: opts.relay,
    });
  });

// --- burrow groups ---
program
  .command('groups')
  .description('List all groups')
  .option('-d, --data-dir <path>', 'Data directory')
  .action((opts) => {
    listGroupsCommand({ dataDir: opts.dataDir });
  });

// --- burrow invite ---
program
  .command('invite')
  .description('Invite a user to a group')
  .argument('<group-id>', 'Group ID (nostr group ID prefix)')
  .argument('<pubkey>', 'Invitee Nostr public key (hex)')
  .option('-k, --key-path <path>', 'Path to Nostr secret key')
  .option('-d, --data-dir <path>', 'Data directory')
  .action(async (groupId, pubkey, opts) => {
    await inviteCommand({
      groupId,
      inviteePubkey: pubkey,
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
    });
  });

// --- burrow send ---
program
  .command('send')
  .description('Send an encrypted message to a group')
  .argument('<group-id>', 'Group ID')
  .argument('<message>', 'Message text')
  .option('-k, --key-path <path>', 'Path to Nostr secret key')
  .option('-d, --data-dir <path>', 'Data directory')
  .action(async (groupId, message, opts) => {
    await sendCommand({
      groupId,
      message,
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
    });
  });

// --- burrow read ---
program
  .command('read')
  .description('Read messages from a group')
  .argument('<group-id>', 'Group ID')
  .option('-n, --limit <number>', 'Number of messages', '50')
  .option('-d, --data-dir <path>', 'Data directory')
  .action((groupId, opts) => {
    readCommand({
      groupId,
      limit: parseInt(opts.limit),
      dataDir: opts.dataDir,
    });
  });

// --- burrow listen ---
program
  .command('listen')
  .description('Listen for new messages in a group (real-time)')
  .argument('<group-id>', 'Group ID')
  .option('-k, --key-path <path>', 'Path to Nostr secret key')
  .option('-d, --data-dir <path>', 'Data directory')
  .action(async (groupId, opts) => {
    await listenCommand({
      groupId,
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
    });
  });

// --- burrow daemon ---
program
  .command('daemon')
  .description('Run persistent listener on ALL groups (JSONL output, auto-reconnect)')
  .option('-k, --key-path <path>', 'Path to Nostr secret key')
  .option('-d, --data-dir <path>', 'Data directory')
  .option('-l, --log-file <path>', 'Path to JSONL log file for OpenClaw integration')
  .option('--reconnect-delay <ms>', 'Reconnect delay in ms', '5000')
  .option('--no-access-control', 'Disable access control (TESTING ONLY)')
  .action(async (opts) => {
    await daemonCommand({
      keyPath: opts.keyPath,
      dataDir: opts.dataDir,
      logFile: opts.logFile,
      reconnectDelay: parseInt(opts.reconnectDelay),
      noAccessControl: !opts.accessControl,
    });
  });

program.parse();
