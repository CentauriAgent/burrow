import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { ContentTypeName } from "./contentType.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
/** @public */
export declare const senderTypes: {
    readonly member: 1;
    readonly external: 2;
    readonly new_member_proposal: 3;
    readonly new_member_commit: 4;
};
/** @public */
export type SenderTypeName = keyof typeof senderTypes;
export type SenderTypeValue = (typeof senderTypes)[SenderTypeName];
export declare const senderTypeEncoder: BufferEncoder<SenderTypeName>;
export declare const encodeSenderType: Encoder<SenderTypeName>;
export declare const decodeSenderType: Decoder<SenderTypeName>;
/** @public */
export interface SenderMember {
    senderType: "member";
    leafIndex: number;
}
/** @public */
export type SenderNonMember = SenderExternal | SenderNewMemberProposal | SenderNewMemberCommit;
/** @public */
export interface SenderExternal {
    senderType: "external";
    senderIndex: number;
}
/** @public */
export interface SenderNewMemberProposal {
    senderType: "new_member_proposal";
}
/** @public */
export interface SenderNewMemberCommit {
    senderType: "new_member_commit";
}
/** @public */
export type Sender = SenderMember | SenderNonMember;
export declare const senderEncoder: BufferEncoder<Sender>;
export declare const encodeSender: Encoder<Sender>;
export declare const decodeSender: Decoder<Sender>;
export declare function getSenderLeafNodeIndex(sender: Sender): number | undefined;
export interface SenderData {
    leafIndex: number;
    generation: number;
    reuseGuard: ReuseGuard;
}
export type ReuseGuard = Uint8Array & {
    length: 4;
};
export declare const reuseGuardEncoder: BufferEncoder<ReuseGuard>;
export declare const encodeReuseGuard: Encoder<ReuseGuard>;
export declare const decodeReuseGuard: Decoder<ReuseGuard>;
export declare const senderDataEncoder: BufferEncoder<SenderData>;
export declare const encodeSenderData: Encoder<SenderData>;
export declare const decodeSenderData: Decoder<SenderData>;
export interface SenderDataAAD {
    groupId: Uint8Array;
    epoch: bigint;
    contentType: ContentTypeName;
}
export declare const senderDataAADEncoder: BufferEncoder<SenderDataAAD>;
export declare const encodeSenderDataAAD: Encoder<SenderDataAAD>;
export declare const decodeSenderDataAAD: Decoder<SenderDataAAD>;
export declare function sampleCiphertext(cs: CiphersuiteImpl, ciphertext: Uint8Array): Uint8Array;
export declare function expandSenderDataKey(cs: CiphersuiteImpl, senderDataSecret: Uint8Array, ciphertext: Uint8Array): Promise<Uint8Array>;
export declare function expandSenderDataNonce(cs: CiphersuiteImpl, senderDataSecret: Uint8Array, ciphertext: Uint8Array): Promise<Uint8Array>;
