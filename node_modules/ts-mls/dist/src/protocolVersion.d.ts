import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export declare const protocolVersions: {
    readonly mls10: 1;
};
/** @public */
export type ProtocolVersionName = keyof typeof protocolVersions;
export type ProtocolVersionValue = (typeof protocolVersions)[ProtocolVersionName];
export declare const protocolVersionEncoder: BufferEncoder<ProtocolVersionName>;
export declare const encodeProtocolVersion: Encoder<ProtocolVersionName>;
export declare const decodeProtocolVersion: Decoder<ProtocolVersionName>;
