import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CredentialTypeName } from "./credentialType.js";
/** @public */
export type Credential = CredentialBasic | CredentialX509;
/** @public */
export interface CredentialBasic {
    credentialType: "basic";
    identity: Uint8Array;
}
/** @public */
export interface CredentialX509 {
    credentialType: "x509";
    certificates: Uint8Array[];
}
/** @public */
export interface CredentialCustom {
    credentialType: CredentialTypeName;
    data: Uint8Array;
}
export declare const credentialBasicEncoder: BufferEncoder<CredentialBasic>;
export declare const encodeCredentialBasic: Encoder<CredentialBasic>;
export declare const credentialX509Encoder: BufferEncoder<CredentialX509>;
export declare const encodeCredentialX509: Encoder<CredentialX509>;
export declare const credentialCustomEncoder: BufferEncoder<CredentialCustom>;
export declare const encodeCredentialCustom: Encoder<CredentialCustom>;
export declare const credentialEncoder: BufferEncoder<Credential>;
export declare const encodeCredential: Encoder<Credential>;
export declare const decodeCredential: Decoder<Credential>;
