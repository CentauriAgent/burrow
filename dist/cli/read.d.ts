/**
 * `burrow read` — Read messages from a group.
 * `burrow listen` — Listen for new messages in real-time.
 */
export declare function readCommand(opts: {
    groupId: string;
    limit?: number;
    dataDir?: string;
}): void;
export declare function listenCommand(opts: {
    groupId: string;
    keyPath?: string;
    dataDir?: string;
}): Promise<void>;
//# sourceMappingURL=read.d.ts.map