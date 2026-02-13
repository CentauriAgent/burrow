import { AuthenticatedContent } from "./authenticatedContent.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { GroupContext } from "./groupContext.js";
import { Proposal } from "./proposal.js";
import { PrivateMessage, PrivateMessageContent } from "./privateMessage.js";
import { SecretTree } from "./secretTree.js";
import { RatchetTree } from "./ratchetTree.js";
import { SenderData } from "./sender.js";
import { KeyRetentionConfig } from "./keyRetentionConfig.js";
import { MlsError } from "./mlsError.js";
import { PaddingConfig } from "./paddingConfig.js";
export interface ProtectApplicationDataResult {
    privateMessage: PrivateMessage;
    newSecretTree: SecretTree;
    consumed: Uint8Array[];
}
export declare function protectApplicationData(signKey: Uint8Array, senderDataSecret: Uint8Array, applicationData: Uint8Array, authenticatedData: Uint8Array, groupContext: GroupContext, secretTree: SecretTree, leafIndex: number, paddingConfig: PaddingConfig, cs: CiphersuiteImpl): Promise<ProtectApplicationDataResult>;
export interface ProtectProposalResult {
    privateMessage: PrivateMessage;
    newSecretTree: SecretTree;
    proposalRef: Uint8Array;
    consumed: Uint8Array[];
}
export declare function protectProposal(signKey: Uint8Array, senderDataSecret: Uint8Array, p: Proposal, authenticatedData: Uint8Array, groupContext: GroupContext, secretTree: SecretTree, leafIndex: number, paddingConfig: PaddingConfig, cs: CiphersuiteImpl): Promise<ProtectProposalResult>;
export interface ProtectResult {
    privateMessage: PrivateMessage;
    tree: SecretTree;
    consumed: Uint8Array[];
}
export declare function protect(senderDataSecret: Uint8Array, authenticatedData: Uint8Array, groupContext: GroupContext, secretTree: SecretTree, content: PrivateMessageContent, leafIndex: number, config: PaddingConfig, cs: CiphersuiteImpl): Promise<ProtectResult>;
export interface UnprotectResult {
    content: AuthenticatedContent;
    tree: SecretTree;
    consumed: Uint8Array[];
}
export declare function unprotectPrivateMessage(senderDataSecret: Uint8Array, msg: PrivateMessage, secretTree: SecretTree, ratchetTree: RatchetTree, groupContext: GroupContext, config: KeyRetentionConfig, cs: CiphersuiteImpl, overrideSignatureKey?: Uint8Array): Promise<UnprotectResult>;
export declare function validateSenderData(senderData: SenderData, tree: RatchetTree): MlsError | undefined;
