/**
 * `burrow invite <pubkey>` — Invite a user to a group by fetching their KeyPackage.
 */
export declare function inviteCommand(opts: {
    groupId: string;
    inviteePubkey: string;
    keyPath?: string;
    dataDir?: string;
}): Promise<void>;
//# sourceMappingURL=invite.d.ts.map