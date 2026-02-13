import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Hash } from "./crypto/hash.js";
import { FramedContent, FramedContentApplicationData, FramedContentAuthData, FramedContentCommitData, FramedContentData, FramedContentProposalData, FramedContentTBS } from "./framedContent.js";
import { WireformatName } from "./wireformat.js";
export interface AuthenticatedContent {
    wireformat: WireformatName;
    content: FramedContent;
    auth: FramedContentAuthData;
}
export type AuthenticatedContentApplication = AuthenticatedContent & {
    content: FramedContentApplicationData & FramedContentData;
};
export type AuthenticatedContentCommit = AuthenticatedContent & {
    content: FramedContentCommitData & FramedContentData;
};
export type AuthenticatedContentProposal = AuthenticatedContent & {
    content: FramedContentProposalData & FramedContentData;
};
export type AuthenticatedContentProposalOrCommit = AuthenticatedContent & {
    content: (FramedContentProposalData | FramedContentCommitData) & FramedContentData;
};
export declare const authenticatedContentEncoder: BufferEncoder<AuthenticatedContent>;
export declare const encodeAuthenticatedContent: Encoder<AuthenticatedContent>;
export declare const decodeAuthenticatedContent: Decoder<AuthenticatedContent>;
export interface AuthenticatedContentTBM {
    contentTbs: FramedContentTBS;
    auth: FramedContentAuthData;
}
export declare const authenticatedContentTBMEncoder: BufferEncoder<AuthenticatedContentTBM>;
export declare const encodeAuthenticatedContentTBM: Encoder<AuthenticatedContentTBM>;
export declare function createMembershipTag(membershipKey: Uint8Array, tbm: AuthenticatedContentTBM, h: Hash): Promise<Uint8Array>;
export declare function verifyMembershipTag(membershipKey: Uint8Array, tbm: AuthenticatedContentTBM, tag: Uint8Array, h: Hash): Promise<boolean>;
export declare function makeProposalRef(proposal: AuthenticatedContent, h: Hash): Promise<Uint8Array>;
