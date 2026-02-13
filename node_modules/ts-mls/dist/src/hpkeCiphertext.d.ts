import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export interface HPKECiphertext {
    kemOutput: Uint8Array;
    ciphertext: Uint8Array;
}
export declare const hpkeCiphertextEncoder: BufferEncoder<HPKECiphertext>;
export declare const encodeHpkeCiphertext: Encoder<HPKECiphertext>;
export declare const decodeHpkeCiphertext: Decoder<HPKECiphertext>;
