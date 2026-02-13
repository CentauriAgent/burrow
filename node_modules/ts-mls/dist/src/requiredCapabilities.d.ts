import { CredentialTypeName } from "./credentialType.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Decoder } from "./codec/tlsDecoder.js";
/** @public */
export interface RequiredCapabilities {
    extensionTypes: number[];
    proposalTypes: number[];
    credentialTypes: CredentialTypeName[];
}
export declare const requiredCapabilitiesEncoder: BufferEncoder<RequiredCapabilities>;
/** @public */
export declare const encodeRequiredCapabilities: Encoder<RequiredCapabilities>;
/** @public */
export declare const decodeRequiredCapabilities: Decoder<RequiredCapabilities>;
