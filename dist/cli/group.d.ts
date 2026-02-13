/**
 * `burrow create-group` — Create a new encrypted group.
 * `burrow groups` — List groups.
 */
export declare function createGroupCommand(opts: {
    name: string;
    description?: string;
    keyPath?: string;
    dataDir?: string;
    relays?: string[];
}): Promise<void>;
export declare function listGroupsCommand(opts: {
    dataDir?: string;
}): void;
//# sourceMappingURL=group.d.ts.map