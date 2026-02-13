/**
 * Nostr relay connection management.
 */

import { SimplePool, finalizeEvent } from 'nostr-tools';
import type { Filter } from 'nostr-tools';
import { randomBytes } from 'node:crypto';

export class RelayPool {
  private pool: SimplePool;
  private relays: string[];

  constructor(relays: string[]) {
    this.pool = new SimplePool();
    this.relays = relays;
  }

  async publish(event: any): Promise<void> {
    const results = await Promise.allSettled(
      this.pool.publish(this.relays, event)
    );
    const successes = results.filter(r => r.status === 'fulfilled').length;
    if (successes === 0) {
      throw new Error('Failed to publish to any relay');
    }
    console.log(`  Published to ${successes}/${this.relays.length} relays`);
  }

  subscribe(
    filters: Filter[],
    onEvent: (event: any) => void,
    onEose?: () => void,
  ): { close: () => void } {
    const sub = this.pool.subscribeMany(this.relays, filters as any, {
      onevent: onEvent,
      oneose: onEose,
    });
    return { close: () => sub.close() };
  }

  async query(filters: Filter[]): Promise<any[]> {
    return await this.pool.querySync(this.relays, filters[0]);
  }

  close(): void {
    this.pool.close(this.relays);
  }
}

export function createSignedEvent(
  kind: number,
  content: string,
  tags: string[][],
  secretKey: Uint8Array,
): any {
  const event = {
    kind,
    content,
    tags,
    created_at: Math.floor(Date.now() / 1000),
  };
  return finalizeEvent(event, secretKey);
}

export function createEphemeralSignedEvent(
  kind: number,
  content: string,
  tags: string[][],
): { event: any; ephemeralSecret: Uint8Array } {
  const ephemeralSecret = new Uint8Array(randomBytes(32));
  const event = createSignedEvent(kind, content, tags, ephemeralSecret);
  return { event, ephemeralSecret };
}
