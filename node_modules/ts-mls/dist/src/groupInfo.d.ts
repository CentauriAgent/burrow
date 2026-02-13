import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Kdf } from "./crypto/kdf.js";
import { Signature } from "./crypto/signature.js";
import { Extension } from "./extension.js";
import { GroupContext } from "./groupContext.js";
import { RatchetTree } from "./ratchetTree.js";
/** @public */
export interface GroupInfoTBS {
    groupContext: GroupContext;
    extensions: Extension[];
    confirmationTag: Uint8Array;
    signer: number;
}
export declare const groupInfoTBSEncoder: BufferEncoder<GroupInfoTBS>;
export declare const encodeGroupInfoTBS: Encoder<GroupInfoTBS>;
export declare const decodeGroupInfoTBS: Decoder<GroupInfoTBS>;
/** @public */
export type GroupInfo = GroupInfoTBS & {
    signature: Uint8Array;
};
export declare const groupInfoEncoder: BufferEncoder<GroupInfo>;
export declare const encodeGroupInfo: Encoder<GroupInfo>;
export declare const decodeGroupInfo: Decoder<GroupInfo>;
export declare function ratchetTreeFromExtension(info: GroupInfo): RatchetTree | undefined;
export declare function signGroupInfo(tbs: GroupInfoTBS, privateKey: Uint8Array, s: Signature): Promise<GroupInfo>;
export declare function verifyGroupInfoSignature(gi: GroupInfo, publicKey: Uint8Array, s: Signature): Promise<boolean>;
export declare function verifyGroupInfoConfirmationTag(gi: GroupInfo, joinerSecret: Uint8Array, pskSecret: Uint8Array, cs: CiphersuiteImpl): Promise<boolean>;
export declare function extractWelcomeSecret(joinerSecret: Uint8Array, pskSecret: Uint8Array, kdf: Kdf): Promise<Uint8Array<ArrayBufferLike>>;
