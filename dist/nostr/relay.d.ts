/**
 * Nostr relay connection management.
 */
import type { Filter } from 'nostr-tools';
export declare class RelayPool {
    private pool;
    private relays;
    constructor(relays: string[]);
    publish(event: any): Promise<void>;
    subscribe(filters: Filter[], onEvent: (event: any) => void, onEose?: () => void): {
        close: () => void;
    };
    query(filters: Filter[]): Promise<any[]>;
    close(): void;
}
export declare function createSignedEvent(kind: number, content: string, tags: string[][], secretKey: Uint8Array): any;
export declare function createEphemeralSignedEvent(kind: number, content: string, tags: string[][]): {
    event: any;
    ephemeralSecret: Uint8Array;
};
//# sourceMappingURL=relay.d.ts.map