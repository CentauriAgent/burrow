import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteName } from "./crypto/ciphersuite.js";
import { Kdf } from "./crypto/kdf.js";
import { Extension } from "./extension.js";
import { ProtocolVersionName } from "./protocolVersion.js";
/** @public */
export interface GroupContext {
    version: ProtocolVersionName;
    cipherSuite: CiphersuiteName;
    groupId: Uint8Array;
    epoch: bigint;
    treeHash: Uint8Array;
    confirmedTranscriptHash: Uint8Array;
    extensions: Extension[];
}
export declare const groupContextEncoder: BufferEncoder<GroupContext>;
export declare const encodeGroupContext: Encoder<GroupContext>;
export declare const decodeGroupContext: Decoder<GroupContext>;
export declare function extractEpochSecret(context: GroupContext, joinerSecret: Uint8Array, kdf: Kdf, pskSecret?: Uint8Array): Promise<Uint8Array<ArrayBufferLike>>;
export declare function extractJoinerSecret(context: GroupContext, previousInitSecret: Uint8Array, commitSecret: Uint8Array, kdf: Kdf): Promise<Uint8Array<ArrayBufferLike>>;
