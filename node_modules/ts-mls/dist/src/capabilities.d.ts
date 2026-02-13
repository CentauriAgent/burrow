import { CredentialTypeName } from "./credentialType.js";
import { CiphersuiteName } from "./crypto/ciphersuite.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Decoder } from "./codec/tlsDecoder.js";
/** @public */
export interface Capabilities {
    versions: ProtocolVersionName[];
    ciphersuites: CiphersuiteName[];
    extensions: number[];
    proposals: number[];
    credentials: CredentialTypeName[];
}
export declare const capabilitiesEncoder: BufferEncoder<Capabilities>;
export declare const encodeCapabilities: Encoder<Capabilities>;
export declare const decodeCapabilities: Decoder<Capabilities>;
