import { AuthenticatedContent } from "./authenticatedContent.js";
import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { ContentTypeName } from "./contentType.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { FramedContentApplicationData, FramedContentAuthDataApplicationOrProposal, FramedContentAuthDataCommit, FramedContentCommitData, FramedContentProposalData } from "./framedContent.js";
import { PaddingConfig } from "./paddingConfig.js";
import { SenderData, SenderDataAAD } from "./sender.js";
/** @public */
export interface PrivateMessage {
    groupId: Uint8Array;
    epoch: bigint;
    contentType: ContentTypeName;
    authenticatedData: Uint8Array;
    encryptedSenderData: Uint8Array;
    ciphertext: Uint8Array;
}
export declare const privateMessageEncoder: BufferEncoder<PrivateMessage>;
export declare const encodePrivateMessage: Encoder<PrivateMessage>;
export declare const decodePrivateMessage: Decoder<PrivateMessage>;
export interface PrivateContentAAD {
    groupId: Uint8Array;
    epoch: bigint;
    contentType: ContentTypeName;
    authenticatedData: Uint8Array;
}
export declare const privateContentAADEncoder: BufferEncoder<PrivateContentAAD>;
export declare const encodePrivateContentAAD: Encoder<PrivateContentAAD>;
export declare const decodePrivateContentAAD: Decoder<PrivateContentAAD>;
export type PrivateMessageContent = PrivateMessageContentApplication | PrivateMessageContentProposal | PrivateMessageContentCommit;
export type PrivateMessageContentApplication = FramedContentApplicationData & {
    auth: FramedContentAuthDataApplicationOrProposal;
};
export type PrivateMessageContentProposal = FramedContentProposalData & {
    auth: FramedContentAuthDataApplicationOrProposal;
};
export type PrivateMessageContentCommit = FramedContentCommitData & {
    auth: FramedContentAuthDataCommit;
};
export declare function decodePrivateMessageContent(contentType: ContentTypeName): Decoder<PrivateMessageContent>;
export declare function privateMessageContentEncoder(config: PaddingConfig): BufferEncoder<PrivateMessageContent>;
export declare function encodePrivateMessageContent(config: PaddingConfig): Encoder<PrivateMessageContent>;
export declare function decryptSenderData(msg: PrivateMessage, senderDataSecret: Uint8Array, cs: CiphersuiteImpl): Promise<SenderData | undefined>;
export declare function encryptSenderData(senderDataSecret: Uint8Array, senderData: SenderData, aad: SenderDataAAD, ciphertext: Uint8Array, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function toAuthenticatedContent(content: PrivateMessageContent, msg: PrivateMessage, senderLeafIndex: number): AuthenticatedContent;
