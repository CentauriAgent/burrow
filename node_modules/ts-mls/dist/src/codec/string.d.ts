import { Decoder } from "./tlsDecoder.js";
import { BufferEncoder, Encoder } from "./tlsEncoder.js";
export declare const stringEncoder: BufferEncoder<string>;
export declare const encodeString: Encoder<string>;
export declare const decodeString: Decoder<string>;
