import { ClientState } from "./clientState.js";
import { CreateCommitResult } from "./createCommit.js";
import { CiphersuiteName, CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { CryptoProvider } from "./crypto/provider.js";
import { Extension } from "./extension.js";
import { KeyPackage, PrivateKeyPackage } from "./keyPackage.js";
import { ResumptionPSKUsageName, PreSharedKeyID } from "./presharedkey.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { RatchetTree } from "./ratchetTree.js";
import { Welcome } from "./welcome.js";
/** @public */
export declare function reinitGroup(state: ClientState, groupId: Uint8Array, version: ProtocolVersionName, cipherSuite: CiphersuiteName, extensions: Extension[], cs: CiphersuiteImpl): Promise<CreateCommitResult>;
/** @public */
export declare function reinitCreateNewGroup(state: ClientState, keyPackage: KeyPackage, privateKeyPackage: PrivateKeyPackage, memberKeyPackages: KeyPackage[], groupId: Uint8Array, cipherSuite: CiphersuiteName, extensions: Extension[], provider?: CryptoProvider): Promise<CreateCommitResult>;
export declare function makeResumptionPsk(state: ClientState, usage: ResumptionPSKUsageName, cs: CiphersuiteImpl): {
    id: PreSharedKeyID;
    secret: Uint8Array;
};
/** @public */
export declare function branchGroup(state: ClientState, keyPackage: KeyPackage, privateKeyPackage: PrivateKeyPackage, memberKeyPackages: KeyPackage[], newGroupId: Uint8Array, cs: CiphersuiteImpl): Promise<CreateCommitResult>;
/** @public */
export declare function joinGroupFromBranch(oldState: ClientState, welcome: Welcome, keyPackage: KeyPackage, privateKeyPackage: PrivateKeyPackage, ratchetTree: RatchetTree | undefined, cs: CiphersuiteImpl): Promise<ClientState>;
/** @public */
export declare function joinGroupFromReinit(suspendedState: ClientState, welcome: Welcome, keyPackage: KeyPackage, privateKeyPackage: PrivateKeyPackage, ratchetTree: RatchetTree | undefined, provider?: CryptoProvider): Promise<ClientState>;
