/**
 * Burrow type definitions — Marmot Protocol types for Nostr + MLS
 */
export declare const MARMOT_KINDS: {
    readonly KEY_PACKAGE: 443;
    readonly WELCOME: 444;
    readonly GROUP_MESSAGE: 445;
    readonly KEY_PACKAGE_RELAY_LIST: 10051;
};
export declare const MARMOT_EXTENSION_ID = 62190;
export declare const LAST_RESORT_EXTENSION_ID = 10;
export interface BurrowConfig {
    secretKeyPath: string;
    dataDir: string;
    relays: string[];
    ciphersuite: string;
}
export interface MarmotGroupData {
    version: number;
    nostrGroupId: Uint8Array;
    name: string;
    description: string;
    adminPubkeys: string[];
    relays: string[];
    imageHash: Uint8Array;
    imageKey: Uint8Array;
    imageNonce: Uint8Array;
}
export interface StoredGroup {
    mlsGroupId: string;
    nostrGroupId: string;
    name: string;
    description: string;
    adminPubkeys: string[];
    relays: string[];
    mlsState: string;
    createdAt: number;
    lastMessageAt: number;
    epoch: number;
}
export interface StoredKeyPackage {
    id: string;
    mlsKeyPackage: string;
    privateKey: string;
    createdAt: number;
    isLastResort: boolean;
}
export interface GroupMessage {
    id: string;
    groupId: string;
    senderPubkey: string;
    content: string;
    kind: number;
    createdAt: number;
    tags: string[][];
}
export interface NostrEvent {
    id?: string;
    kind: number;
    created_at: number;
    pubkey: string;
    content: string;
    tags: string[][];
    sig?: string;
}
export declare const DEFAULT_RELAYS: string[];
export declare const DEFAULT_CIPHERSUITE = "MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519";
//# sourceMappingURL=index.d.ts.map