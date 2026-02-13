import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
declare const nodeTypes: {
    readonly leaf: 1;
    readonly parent: 2;
};
export type NodeTypeName = keyof typeof nodeTypes;
export type NodeTypeValue = (typeof nodeTypes)[NodeTypeName];
export declare const nodeTypeEncoder: BufferEncoder<NodeTypeName>;
export declare const encodeNodeType: Encoder<NodeTypeName>;
export declare const decodeNodeType: Decoder<NodeTypeName>;
export {};
