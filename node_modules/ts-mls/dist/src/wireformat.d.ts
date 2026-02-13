import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
export declare const wireformats: {
    readonly mls_public_message: 1;
    readonly mls_private_message: 2;
    readonly mls_welcome: 3;
    readonly mls_group_info: 4;
    readonly mls_key_package: 5;
};
export type WireformatName = keyof typeof wireformats;
export type WireformatValue = (typeof wireformats)[WireformatName];
export declare const wireformatEncoder: BufferEncoder<WireformatName>;
export declare const encodeWireformat: Encoder<WireformatName>;
export declare const decodeWireformat: Decoder<WireformatName>;
