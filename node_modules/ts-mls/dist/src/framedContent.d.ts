import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Commit } from "./commit.js";
import { ContentTypeName } from "./contentType.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Hash } from "./crypto/hash.js";
import { Signature } from "./crypto/signature.js";
import { GroupContext } from "./groupContext.js";
import { WireformatName } from "./wireformat.js";
import { Proposal } from "./proposal.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { Sender, SenderExternal, SenderMember, SenderNewMemberCommit, SenderNewMemberProposal } from "./sender.js";
/** @public */
export type FramedContentInfo = FramedContentApplicationData | FramedContentProposalData | FramedContentCommitData;
/** @public */
export interface FramedContentApplicationData {
    contentType: "application";
    applicationData: Uint8Array;
}
/** @public */
export interface FramedContentProposalData {
    contentType: "proposal";
    proposal: Proposal;
}
/** @public */
export interface FramedContentCommitData {
    contentType: "commit";
    commit: Commit;
}
export declare const framedContentApplicationDataEncoder: BufferEncoder<FramedContentApplicationData>;
export declare const encodeFramedContentApplicationData: Encoder<FramedContentApplicationData>;
export declare const framedContentProposalDataEncoder: BufferEncoder<FramedContentProposalData>;
export declare const encodeFramedContentProposalData: Encoder<FramedContentProposalData>;
export declare const framedContentCommitDataEncoder: BufferEncoder<FramedContentCommitData>;
export declare const encodeFramedContentCommitData: Encoder<FramedContentCommitData>;
export declare const framedContentInfoEncoder: BufferEncoder<FramedContentInfo>;
export declare const encodeFramedContentInfo: Encoder<FramedContentInfo>;
export declare const decodeFramedContentApplicationData: Decoder<FramedContentApplicationData>;
export declare const decodeFramedContentProposalData: Decoder<FramedContentProposalData>;
export declare const decodeFramedContentCommitData: Decoder<FramedContentCommitData>;
export declare const decodeFramedContentInfo: Decoder<FramedContentInfo>;
export declare function toTbs(content: FramedContent, wireformat: WireformatName, context: GroupContext): FramedContentTBS;
/** @public */
export type FramedContent = FramedContentData & FramedContentInfo;
/** @public */
export interface FramedContentData {
    groupId: Uint8Array;
    epoch: bigint;
    sender: Sender;
    authenticatedData: Uint8Array;
}
export type FramedContentMember = FramedContent & {
    sender: SenderMember;
};
export type FramedContentNewMemberCommit = FramedContent & {
    sender: SenderNewMemberCommit;
};
export type FramedContentExternal = FramedContent & {
    sender: SenderExternal;
};
export type FramedContentNewMemberProposal = FramedContent & {
    sender: SenderNewMemberProposal;
};
export type FramedContentCommit = FramedContentData & FramedContentCommitData;
export type FramedContentApplicationOrProposal = FramedContentData & (FramedContentApplicationData | FramedContentProposalData);
export declare const framedContentEncoder: BufferEncoder<FramedContent>;
export declare const encodeFramedContent: Encoder<FramedContent>;
export declare const decodeFramedContent: Decoder<FramedContent>;
type SenderInfo = SenderInfoMember | SenderInfoNewMemberCommit | SenderInfoExternal | SenderInfoNewMemberProposal;
type SenderInfoMember = {
    senderType: "member";
    context: GroupContext;
};
type SenderInfoNewMemberCommit = {
    senderType: "new_member_commit";
    context: GroupContext;
};
type SenderInfoExternal = {
    senderType: "external";
};
type SenderInfoNewMemberProposal = {
    senderType: "new_member_proposal";
};
export declare const senderInfoEncoder: BufferEncoder<SenderInfo>;
export declare const encodeSenderInfo: Encoder<SenderInfo>;
export type FramedContentTBS = {
    protocolVersion: ProtocolVersionName;
    wireformat: WireformatName;
    content: FramedContent;
} & SenderInfo;
export type FramedContentTBSCommit = FramedContentTBS & {
    content: FramedContentCommit;
};
export type FramedContentTBSApplicationOrProposal = FramedContentTBS & {
    content: FramedContentApplicationOrProposal;
};
export type FramedContentTBSExternal = FramedContentTBS & (SenderInfoExternal | SenderInfoNewMemberCommit | SenderInfoNewMemberProposal);
export declare const framedContentTBSEncoder: BufferEncoder<FramedContentTBS>;
export declare const encodeFramedContentTBS: Encoder<FramedContentTBS>;
/** @public */
export type FramedContentAuthData = FramedContentAuthDataCommit | FramedContentAuthDataApplicationOrProposal;
/** @public */
export type FramedContentAuthDataCommit = {
    signature: Uint8Array;
} & FramedContentAuthDataContentCommit;
/** @public */
export type FramedContentAuthDataApplicationOrProposal = {
    signature: Uint8Array;
} & FramedContentAuthDataContentApplicationOrProposal;
/** @public */
export type FramedContentAuthDataContentCommit = {
    contentType: "commit";
    confirmationTag: Uint8Array;
};
/** @public */
export type FramedContentAuthDataContentApplicationOrProposal = {
    contentType: Exclude<ContentTypeName, "commit">;
};
export declare const framedContentAuthDataEncoder: BufferEncoder<FramedContentAuthData>;
export declare const encodeFramedContentAuthData: Encoder<FramedContentAuthData>;
export declare const decodeFramedContentAuthDataCommit: Decoder<FramedContentAuthDataContentCommit>;
export declare function decodeFramedContentAuthData(contentType: ContentTypeName): Decoder<FramedContentAuthData>;
export declare function verifyFramedContentSignature(signKey: Uint8Array, wireformat: WireformatName, content: FramedContent, auth: FramedContentAuthData, context: GroupContext, s: Signature): Promise<boolean>;
export declare function signFramedContentTBS(signKey: Uint8Array, tbs: FramedContentTBS, s: Signature): Promise<Uint8Array>;
export declare function signFramedContentApplicationOrProposal(signKey: Uint8Array, tbs: FramedContentTBSApplicationOrProposal, cs: CiphersuiteImpl): Promise<FramedContentAuthDataApplicationOrProposal>;
export declare function createConfirmationTag(confirmationKey: Uint8Array, confirmedTranscriptHash: Uint8Array, h: Hash): Promise<Uint8Array>;
export declare function verifyConfirmationTag(confirmationKey: Uint8Array, tag: Uint8Array, confirmedTranscriptHash: Uint8Array, h: Hash): Promise<boolean>;
export declare function createContentCommitSignature(groupContext: GroupContext, wireformat: WireformatName, c: Commit, sender: Sender, authenticatedData: Uint8Array, signKey: Uint8Array, s: Signature): Promise<{
    framedContent: FramedContentCommit;
    signature: Uint8Array;
}>;
export {};
