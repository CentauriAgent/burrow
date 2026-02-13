import { AuthenticatedContent } from "./authenticatedContent.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Hash } from "./crypto/hash.js";
import { Extension } from "./extension.js";
import { FramedContentCommit } from "./framedContent.js";
import { GroupContext } from "./groupContext.js";
import { KeyPackage, PrivateKeyPackage } from "./keyPackage.js";
import { KeySchedule } from "./keySchedule.js";
import { PreSharedKeyID } from "./presharedkey.js";
import { RatchetTree } from "./ratchetTree.js";
import { SecretTree } from "./secretTree.js";
import { LeafIndex } from "./treemath.js";
import { Welcome } from "./welcome.js";
import { WireformatName } from "./wireformat.js";
import { ProposalOrRef } from "./proposalOrRefType.js";
import { Proposal, ProposalAdd, ProposalExternalInit, ProposalGroupContextExtensions, ProposalPSK, ProposalReinit, ProposalRemove, ProposalUpdate, Reinit } from "./proposal.js";
import { PrivateKeyPath } from "./privateKeyPath.js";
import { UnappliedProposals, ProposalWithSender } from "./unappliedProposals.js";
import { PskIndex } from "./pskIndex.js";
import { ValidationError, MlsError } from "./mlsError.js";
import { Signature } from "./crypto/signature.js";
import { LeafNode, LeafNodeCommit, LeafNodeUpdate } from "./leafNode.js";
import { AuthenticationService } from "./authenticationService.js";
import { LifetimeConfig } from "./lifetimeConfig.js";
import { ClientConfig } from "./clientConfig.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { GroupActiveState } from "./groupActiveState.js";
import { EpochReceiverData } from "./epochReceiverData.js";
import { Decoder } from "./codec/tlsDecoder.js";
/** @public */
export type ClientState = GroupState & {
    clientConfig: ClientConfig;
};
/** @public */
export interface GroupState {
    groupContext: GroupContext;
    keySchedule: KeySchedule;
    secretTree: SecretTree;
    ratchetTree: RatchetTree;
    privatePath: PrivateKeyPath;
    signaturePrivateKey: Uint8Array;
    unappliedProposals: UnappliedProposals;
    confirmationTag: Uint8Array;
    historicalReceiverData: Map<bigint, EpochReceiverData>;
    groupActiveState: GroupActiveState;
}
export declare const groupStateEncoder: BufferEncoder<GroupState>;
/** @public */
export declare const encodeGroupState: Encoder<GroupState>;
/** @public */
export declare const decodeGroupState: Decoder<GroupState>;
export declare const groupStateEncoderWithoutTree: BufferEncoder<GroupState>;
export declare const encodeGroupStateWithoutTree: Encoder<GroupState>;
export declare function decodeGroupStateWithoutTree(ratchetTree: RatchetTree): Decoder<GroupState>;
export declare function getOwnLeafNode(state: ClientState): LeafNode;
export declare function getGroupMembers(state: ClientState): LeafNode[];
export declare function extractFromGroupMembers<T>(state: ClientState, exclude: (l: LeafNode) => boolean, map: (l: LeafNode) => T): T[];
export declare function checkCanSendApplicationMessages(state: ClientState): void;
export declare function checkCanSendHandshakeMessages(state: ClientState): void;
export interface Proposals {
    add: {
        senderLeafIndex: number | undefined;
        proposal: ProposalAdd;
    }[];
    update: {
        senderLeafIndex: number | undefined;
        proposal: ProposalUpdate;
    }[];
    remove: {
        senderLeafIndex: number | undefined;
        proposal: ProposalRemove;
    }[];
    psk: {
        senderLeafIndex: number | undefined;
        proposal: ProposalPSK;
    }[];
    reinit: {
        senderLeafIndex: number | undefined;
        proposal: ProposalReinit;
    }[];
    external_init: {
        senderLeafIndex: number | undefined;
        proposal: ProposalExternalInit;
    }[];
    group_context_extensions: {
        senderLeafIndex: number | undefined;
        proposal: ProposalGroupContextExtensions;
    }[];
}
export declare function validateRatchetTree(tree: RatchetTree, groupContext: GroupContext, config: LifetimeConfig, authService: AuthenticationService, treeHash: Uint8Array, cs: CiphersuiteImpl): Promise<MlsError | undefined>;
export declare function validateLeafNodeUpdateOrCommit(leafNode: LeafNodeCommit | LeafNodeUpdate, leafIndex: number, groupContext: GroupContext, authService: AuthenticationService, s: Signature): Promise<MlsError | undefined>;
export declare function throwIfDefined(err: MlsError | undefined): void;
export declare function validateLeafNodeCredentialAndKeyUniqueness(tree: RatchetTree, leafNode: LeafNode, existingLeafIndex?: number): Promise<ValidationError | undefined>;
export interface ApplyProposalsResult {
    tree: RatchetTree;
    pskSecret: Uint8Array;
    pskIds: PreSharedKeyID[];
    needsUpdatePath: boolean;
    additionalResult: ApplyProposalsData;
    selfRemoved: boolean;
    allProposals: ProposalWithSender[];
}
export type ApplyProposalsData = {
    kind: "memberCommit";
    addedLeafNodes: [LeafIndex, KeyPackage][];
    extensions: Extension[];
} | {
    kind: "externalCommit";
    externalInitSecret: Uint8Array;
    newMemberLeafIndex: LeafIndex;
} | {
    kind: "reinit";
    reinit: Reinit;
};
export declare function applyProposals(state: ClientState, proposals: ProposalOrRef[], committerLeafIndex: LeafIndex | undefined, pskSearch: PskIndex, sentByClient: boolean, cs: CiphersuiteImpl): Promise<ApplyProposalsResult>;
/** @public */
export declare function makePskIndex(state: ClientState | undefined, externalPsks: Record<string, Uint8Array>): PskIndex;
export declare function nextEpochContext(groupContext: GroupContext, wireformat: WireformatName, content: FramedContentCommit, signature: Uint8Array, updatedTreeHash: Uint8Array, confirmationTag: Uint8Array, h: Hash): Promise<GroupContext>;
/** @public */
export declare function joinGroup(welcome: Welcome, keyPackage: KeyPackage, privateKeys: PrivateKeyPackage, pskSearch: PskIndex, cs: CiphersuiteImpl, ratchetTree?: RatchetTree, resumingFromState?: ClientState, clientConfig?: ClientConfig): Promise<ClientState>;
/** @public */
export declare function joinGroupWithExtensions(welcome: Welcome, keyPackage: KeyPackage, privateKeys: PrivateKeyPackage, pskSearch: PskIndex, cs: CiphersuiteImpl, ratchetTree?: RatchetTree, resumingFromState?: ClientState, clientConfig?: ClientConfig): Promise<[ClientState, Extension[]]>;
/** @public */
export declare function createGroup(groupId: Uint8Array, keyPackage: KeyPackage, privateKeyPackage: PrivateKeyPackage, extensions: Extension[], cs: CiphersuiteImpl, clientConfig?: ClientConfig): Promise<ClientState>;
export declare function exportSecret(publicKey: Uint8Array, cs: CiphersuiteImpl): Promise<{
    enc: Uint8Array;
    secret: Uint8Array;
}>;
export declare function processProposal(state: ClientState, content: AuthenticatedContent, proposal: Proposal, h: Hash): Promise<ClientState>;
export declare function addHistoricalReceiverData(state: ClientState): [Map<bigint, EpochReceiverData>, Uint8Array[]];
