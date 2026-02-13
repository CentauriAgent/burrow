/**
 * Nostr relay connection management.
 */
import { SimplePool, finalizeEvent } from 'nostr-tools';
export class RelayPool {
    pool;
    relays;
    constructor(relays) {
        this.pool = new SimplePool();
        this.relays = relays;
    }
    async publish(event) {
        const results = await Promise.allSettled(this.pool.publish(this.relays, event));
        const successes = results.filter(r => r.status === 'fulfilled').length;
        if (successes === 0) {
            throw new Error('Failed to publish to any relay');
        }
        console.log(`  Published to ${successes}/${this.relays.length} relays`);
    }
    subscribe(filters, onEvent, onEose) {
        const sub = this.pool.subscribeMany(this.relays, filters, {
            onevent: onEvent,
            oneose: onEose,
        });
        return { close: () => sub.close() };
    }
    async query(filters) {
        return await this.pool.querySync(this.relays, filters[0]);
    }
    close() {
        this.pool.close(this.relays);
    }
}
export function createSignedEvent(kind, content, tags, secretKey) {
    const event = {
        kind,
        content,
        tags,
        created_at: Math.floor(Date.now() / 1000),
    };
    return finalizeEvent(event, secretKey);
}
export function createEphemeralSignedEvent(kind, content, tags) {
    const { randomBytes } = require('node:crypto');
    const ephemeralSecret = new Uint8Array(randomBytes(32));
    const event = createSignedEvent(kind, content, tags, ephemeralSecret);
    return { event, ephemeralSecret };
}
//# sourceMappingURL=relay.js.map