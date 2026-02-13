import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export declare const credentialTypes: {
    readonly basic: 1;
    readonly x509: 2;
};
/** @public */
export type CredentialTypeName = keyof typeof credentialTypes;
export type CredentialTypeValue = (typeof credentialTypes)[CredentialTypeName];
export declare const credentialTypeEncoder: BufferEncoder<CredentialTypeName>;
export declare const encodeCredentialType: Encoder<CredentialTypeName>;
export declare const decodeCredentialType: Decoder<CredentialTypeName>;
