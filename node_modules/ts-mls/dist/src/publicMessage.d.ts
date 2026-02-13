import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Extension } from "./extension.js";
import { ExternalSender } from "./externalSender.js";
import { FramedContent, FramedContentAuthData } from "./framedContent.js";
import { GroupContext } from "./groupContext.js";
import { RatchetTree } from "./ratchetTree.js";
import { SenderTypeName } from "./sender.js";
/** @public */
export type PublicMessageInfo = PublicMessageInfoMember | PublicMessageInfoMemberOther;
/** @public */
export type PublicMessageInfoMember = {
    senderType: "member";
    membershipTag: Uint8Array;
};
/** @public */
export type PublicMessageInfoMemberOther = {
    senderType: Exclude<SenderTypeName, "member">;
};
export declare const publicMessageInfoEncoder: BufferEncoder<PublicMessageInfo>;
export declare const encodePublicMessageInfo: Encoder<PublicMessageInfo>;
export declare function decodePublicMessageInfo(senderType: SenderTypeName): Decoder<PublicMessageInfo>;
/** @public */
export type PublicMessage = {
    content: FramedContent;
    auth: FramedContentAuthData;
} & PublicMessageInfo;
export type MemberPublicMessage = PublicMessage & PublicMessageInfoMember;
export type ExternalPublicMessage = PublicMessage & PublicMessageInfoMemberOther;
export declare const publicMessageEncoder: BufferEncoder<PublicMessage>;
export declare const encodePublicMessage: Encoder<PublicMessage>;
export declare const decodePublicMessage: Decoder<PublicMessage>;
export declare function findSignaturePublicKey(ratchetTree: RatchetTree, groupContext: GroupContext, framedContent: FramedContent): Uint8Array;
export declare function senderFromExtension(extensions: Extension[], senderIndex: number): ExternalSender | undefined;
