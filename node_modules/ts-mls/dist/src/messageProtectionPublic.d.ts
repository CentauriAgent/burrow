import { AuthenticatedContent, AuthenticatedContentProposalOrCommit } from "./authenticatedContent.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { GroupContext } from "./groupContext.js";
import { Proposal } from "./proposal.js";
import { PublicMessage } from "./publicMessage.js";
import { RatchetTree } from "./ratchetTree.js";
import { SenderNonMember } from "./sender.js";
export interface ProtectProposalPublicResult {
    publicMessage: PublicMessage;
}
export declare function protectProposalPublic(signKey: Uint8Array, membershipKey: Uint8Array, groupContext: GroupContext, authenticatedData: Uint8Array, proposal: Proposal, leafIndex: number, cs: CiphersuiteImpl): Promise<ProtectProposalPublicResult>;
export declare function protectExternalProposalPublic(signKey: Uint8Array, groupContext: GroupContext, authenticatedData: Uint8Array, proposal: Proposal, sender: SenderNonMember, cs: CiphersuiteImpl): Promise<ProtectProposalPublicResult>;
export declare function protectPublicMessage(membershipKey: Uint8Array, groupContext: GroupContext, content: AuthenticatedContent, cs: CiphersuiteImpl): Promise<PublicMessage>;
export interface ProtectCommitPublicResult {
    publicMessage: PublicMessage;
}
export declare function unprotectPublicMessage(membershipKey: Uint8Array, groupContext: GroupContext, ratchetTree: RatchetTree, msg: PublicMessage, cs: CiphersuiteImpl, overrideSignatureKey?: Uint8Array): Promise<AuthenticatedContentProposalOrCommit>;
