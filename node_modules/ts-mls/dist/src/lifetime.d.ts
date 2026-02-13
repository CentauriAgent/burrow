import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Decoder } from "./codec/tlsDecoder.js";
/** @public */
export interface Lifetime {
    notBefore: bigint;
    notAfter: bigint;
}
export declare const lifetimeEncoder: BufferEncoder<Lifetime>;
export declare const encodeLifetime: Encoder<Lifetime>;
export declare const decodeLifetime: Decoder<Lifetime>;
/** @public */
export declare const defaultLifetime: Lifetime;
