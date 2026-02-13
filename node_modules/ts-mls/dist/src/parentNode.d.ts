import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export interface ParentNode {
    hpkePublicKey: Uint8Array;
    parentHash: Uint8Array;
    unmergedLeaves: number[];
}
export declare const parentNodeEncoder: BufferEncoder<ParentNode>;
export declare const encodeParentNode: Encoder<ParentNode>;
export declare const decodeParentNode: Decoder<ParentNode>;
