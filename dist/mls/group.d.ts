/**
 * MLS Group management per MIP-01, MIP-02, MIP-03.
 */
import { type GroupState, type CiphersuiteName, type KeyPackage, type CreateCommitResult } from 'ts-mls';
import type { NostrIdentity } from '../crypto/identity.js';
export interface BurrowGroup {
    state: GroupState;
    nostrGroupId: Uint8Array;
    name: string;
    relays: string[];
}
/**
 * Create a new MLS group per MIP-01.
 */
export declare function createMarmotGroup(identity: NostrIdentity, opts: {
    name: string;
    description?: string;
    relays: string[];
    ciphersuiteName?: CiphersuiteName;
}): Promise<{
    group: BurrowGroup;
    encodedState: Uint8Array;
}>;
/**
 * Add a member to the group by their KeyPackage.
 */
export declare function addMember(state: GroupState, memberKeyPackage: KeyPackage, ciphersuiteName?: CiphersuiteName): Promise<CreateCommitResult>;
/**
 * Create an encrypted application message per MIP-03.
 */
export declare function createGroupMsg(state: GroupState, content: Uint8Array, ciphersuiteName?: CiphersuiteName): Promise<{
    message: Uint8Array;
    newState: GroupState;
}>;
/**
 * Process an incoming MLS message.
 */
export declare function processGroupMessage(state: GroupState, messageBytes: Uint8Array, ciphersuiteName?: CiphersuiteName): Promise<any>;
/**
 * Get the exporter_secret for the current epoch.
 */
export declare function getExporterSecret(state: GroupState, ciphersuiteName?: CiphersuiteName): Promise<Uint8Array>;
export declare function serializeGroupState(state: GroupState): Uint8Array;
export declare function deserializeGroupState(data: Uint8Array): GroupState;
//# sourceMappingURL=group.d.ts.map