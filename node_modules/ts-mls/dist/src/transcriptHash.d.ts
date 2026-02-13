import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Hash } from "./crypto/hash.js";
import { FramedContentCommit } from "./framedContent.js";
import { WireformatName } from "./wireformat.js";
export interface ConfirmedTranscriptHashInput {
    wireformat: WireformatName;
    content: FramedContentCommit;
    signature: Uint8Array;
}
export declare const confirmedTranscriptHashInputEncoder: BufferEncoder<ConfirmedTranscriptHashInput>;
export declare const encodeConfirmedTranscriptHashInput: Encoder<ConfirmedTranscriptHashInput>;
export declare const decodeConfirmedTranscriptHashInput: Decoder<ConfirmedTranscriptHashInput>;
export declare function createConfirmedHash(interimTranscriptHash: Uint8Array, input: ConfirmedTranscriptHashInput, hash: Hash): Promise<Uint8Array>;
export declare function createInterimHash(confirmedHash: Uint8Array, confirmationTag: Uint8Array, hash: Hash): Promise<Uint8Array>;
