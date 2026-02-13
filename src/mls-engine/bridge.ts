/**
 * Bridge to the burrow-mls Rust binary.
 *
 * The Rust binary runs in daemon mode, keeping MDK state in memory.
 * This module spawns it as a child process and communicates via JSON lines on stdin/stdout.
 */

import { spawn, type ChildProcess } from 'node:child_process';
import { createInterface, type Interface } from 'node:readline';
import { join } from 'node:path';
import { existsSync } from 'node:fs';

export interface MlsBridgeOptions {
  secretKey: string;
  stateDir?: string;
  binaryPath?: string;
}

type PendingRequest = {
  resolve: (value: any) => void;
  reject: (error: Error) => void;
};

export class MlsBridge {
  private process: ChildProcess | null = null;
  private rl: Interface | null = null;
  private ready = false;
  private readyPromise: Promise<void> | null = null;
  private responseQueue: ((line: string) => void)[] = [];
  private pubkey: string = '';

  constructor(private options: MlsBridgeOptions) {}

  /**
   * Find the burrow-mls binary. Checks:
   * 1. Explicit path from options
   * 2. target/release/burrow-mls (workspace build)
   * 3. target/debug/burrow-mls (dev build)
   * 4. System PATH
   */
  private findBinary(): string {
    if (this.options.binaryPath) return this.options.binaryPath;

    const candidates = [
      join(__dirname, '../../target/release/burrow-mls'),
      join(__dirname, '../../target/debug/burrow-mls'),
    ];

    for (const candidate of candidates) {
      if (existsSync(candidate)) return candidate;
    }

    // Fall back to PATH
    return 'burrow-mls';
  }

  /** Start the daemon process */
  async start(): Promise<void> {
    if (this.process) return;

    const binary = this.findBinary();
    const args = ['daemon', '--secret-key', this.options.secretKey];
    if (this.options.stateDir) {
      args.push('--state-dir', this.options.stateDir);
    }

    this.process = spawn(binary, args, {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    this.process.on('exit', (code) => {
      this.ready = false;
      this.process = null;
      if (code !== 0) {
        console.error(`burrow-mls daemon exited with code ${code}`);
      }
    });

    this.process.stderr?.on('data', (data: Buffer) => {
      const msg = data.toString().trim();
      if (msg) console.error(`[burrow-mls] ${msg}`);
    });

    // Read stdout line by line
    this.rl = createInterface({ input: this.process.stdout! });
    this.rl.on('line', (line: string) => {
      const handler = this.responseQueue.shift();
      if (handler) {
        handler(line);
      }
    });

    // Wait for "ready" message
    const firstLine = await this.readLine();
    const parsed = JSON.parse(firstLine);
    if (parsed.type !== 'ready') {
      throw new Error(`Expected ready message, got: ${firstLine}`);
    }
    this.pubkey = parsed.pubkey;
    this.ready = true;
  }

  /** Send a command and get the response */
  async command(cmd: Record<string, any>): Promise<any> {
    if (!this.process || !this.ready) {
      throw new Error('MLS bridge not started');
    }

    const line = JSON.stringify(cmd);
    this.process.stdin!.write(line + '\n');

    const response = await this.readLine();
    const parsed = JSON.parse(response);

    if (parsed.type === 'error') {
      throw new Error(parsed.error);
    }

    return parsed;
  }

  private readLine(): Promise<string> {
    return new Promise((resolve) => {
      this.responseQueue.push(resolve);
    });
  }

  /** Stop the daemon */
  stop(): void {
    if (this.process) {
      this.process.stdin?.end();
      this.process.kill();
      this.process = null;
      this.ready = false;
    }
    if (this.rl) {
      this.rl.close();
      this.rl = null;
    }
  }

  get publicKey(): string {
    return this.pubkey;
  }

  // === Convenience methods ===

  async keygen(relays?: string[]): Promise<{
    key_package_base64: string;
    tags: string[][];
    pubkey_hex: string;
  }> {
    return this.command({ command: 'keygen', relays: relays || [] });
  }

  async createGroup(opts: {
    name: string;
    description?: string;
    relays?: string[];
    adminPubkeys?: string[];
    memberKeyPackageEvents?: string[];
  }): Promise<any> {
    return this.command({
      command: 'create_group',
      name: opts.name,
      description: opts.description || '',
      relays: opts.relays || [],
      admin_pubkeys: opts.adminPubkeys,
      member_key_package_events: opts.memberKeyPackageEvents || [],
    });
  }

  async mergePendingCommit(mlsGroupIdHex: string): Promise<any> {
    return this.command({
      command: 'merge_pending_commit',
      mls_group_id_hex: mlsGroupIdHex,
    });
  }

  async addMembers(mlsGroupIdHex: string, keyPackageEventsJson: string[]): Promise<any> {
    return this.command({
      command: 'add_members',
      mls_group_id_hex: mlsGroupIdHex,
      key_package_events: keyPackageEventsJson,
    });
  }

  async listGroups(): Promise<any> {
    return this.command({ command: 'list_groups' });
  }

  async processWelcome(wrapperEventIdHex: string, welcomeRumorJson: string): Promise<any> {
    return this.command({
      command: 'process_welcome',
      wrapper_event_id_hex: wrapperEventIdHex,
      welcome_rumor_json: welcomeRumorJson,
    });
  }

  async acceptWelcome(welcomeEventIdHex: string): Promise<any> {
    return this.command({
      command: 'accept_welcome',
      welcome_event_id_hex: welcomeEventIdHex,
    });
  }

  async sendMessage(mlsGroupIdHex: string, content: string): Promise<any> {
    return this.command({
      command: 'send_message',
      mls_group_id_hex: mlsGroupIdHex,
      content,
    });
  }

  async processMessage(eventJson: string): Promise<any> {
    return this.command({
      command: 'process_message',
      event_json: eventJson,
    });
  }

  async exportSecret(mlsGroupIdHex: string): Promise<any> {
    return this.command({
      command: 'export_secret',
      mls_group_id_hex: mlsGroupIdHex,
    });
  }
}
