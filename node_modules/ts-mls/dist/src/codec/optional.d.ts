import { Decoder } from "./tlsDecoder.js";
import { BufferEncoder } from "./tlsEncoder.js";
export declare function optionalEncoder<T>(encodeT: BufferEncoder<T>): BufferEncoder<T | undefined>;
export declare function decodeOptional<T>(decodeT: Decoder<T>): Decoder<T | undefined>;
