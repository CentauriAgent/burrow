import { ClientState } from "./clientState.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { GroupContext } from "./groupContext.js";
import { GroupInfo } from "./groupInfo.js";
import { KeyPackage, PrivateKeyPackage } from "./keyPackage.js";
import { MLSMessage } from "./message.js";
import { PrivateKeyPath } from "./privateKeyPath.js";
import { Proposal } from "./proposal.js";
import { PskIndex } from "./pskIndex.js";
import { RatchetTree } from "./ratchetTree.js";
import { LeafIndex, NodeIndex } from "./treemath.js";
import { UpdatePath } from "./updatePath.js";
import { Welcome } from "./welcome.js";
import { ClientConfig } from "./clientConfig.js";
import { Extension } from "./extension.js";
import { PublicMessage } from "./publicMessage.js";
/** @public */
export interface MLSContext {
    state: ClientState;
    cipherSuite: CiphersuiteImpl;
    pskIndex?: PskIndex;
}
/** @public */
export interface CreateCommitResult {
    newState: ClientState;
    welcome: Welcome | undefined;
    commit: MLSMessage;
    consumed: Uint8Array[];
}
/** @public */
export interface CreateCommitOptions {
    wireAsPublicMessage?: boolean;
    extraProposals?: Proposal[];
    ratchetTreeExtension?: boolean;
    groupInfoExtensions?: Extension[];
    authenticatedData?: Uint8Array;
}
/** @public */
export declare function createCommit(context: MLSContext, options?: CreateCommitOptions): Promise<CreateCommitResult>;
export declare function createGroupInfo(groupContext: GroupContext, confirmationTag: Uint8Array, state: ClientState, extensions: Extension[], cs: CiphersuiteImpl): Promise<GroupInfo>;
export declare function createGroupInfoWithRatchetTree(groupContext: GroupContext, confirmationTag: Uint8Array, state: ClientState, tree: RatchetTree, extensions: Extension[], cs: CiphersuiteImpl): Promise<GroupInfo>;
/** @public */
export declare function createGroupInfoWithExternalPub(state: ClientState, extensions: Extension[], cs: CiphersuiteImpl): Promise<GroupInfo>;
/** @public */
export declare function createGroupInfoWithExternalPubAndRatchetTree(state: ClientState, extensions: Extension[], cs: CiphersuiteImpl): Promise<GroupInfo>;
export declare function applyUpdatePathSecret(tree: RatchetTree, privatePath: PrivateKeyPath, senderLeafIndex: LeafIndex, gc: GroupContext, path: UpdatePath, excludeNodes: NodeIndex[], cs: CiphersuiteImpl): Promise<{
    nodeIndex: NodeIndex;
    pathSecret: Uint8Array;
}>;
/** @public */
export declare function joinGroupExternal(groupInfo: GroupInfo, keyPackage: KeyPackage, privateKeys: PrivateKeyPackage, resync: boolean, cs: CiphersuiteImpl, tree?: RatchetTree, clientConfig?: ClientConfig, authenticatedData?: Uint8Array): Promise<{
    publicMessage: PublicMessage;
    newState: ClientState;
}>;
export declare function filterNewLeaves(resolution: NodeIndex[], excludeNodes: NodeIndex[]): NodeIndex[];
