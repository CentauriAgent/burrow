import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
declare const leafNodeSources: {
    readonly key_package: 1;
    readonly update: 2;
    readonly commit: 3;
};
export type LeafNodeSourceName = keyof typeof leafNodeSources;
export type LeafNodeSourceValue = (typeof leafNodeSources)[LeafNodeSourceName];
export declare const leafNodeSourceEncoder: BufferEncoder<LeafNodeSourceName>;
export declare const encodeLeafNodeSource: Encoder<LeafNodeSourceName>;
export declare const decodeLeafNodeSource: Decoder<LeafNodeSourceName>;
export {};
