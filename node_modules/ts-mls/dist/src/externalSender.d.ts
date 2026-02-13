import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Credential } from "./credential.js";
/** @public */
export interface ExternalSender {
    signaturePublicKey: Uint8Array;
    credential: Credential;
}
export declare const externalSenderEncoder: BufferEncoder<ExternalSender>;
/** @public */
export declare const encodeExternalSender: Encoder<ExternalSender>;
/** @public */
export declare const decodeExternalSender: Decoder<ExternalSender>;
