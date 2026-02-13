import { decodeCredentialType, credentialTypeEncoder } from "./credentialType.js";
import { ciphersuiteEncoder, decodeCiphersuite } from "./crypto/ciphersuite.js";
import { decodeProtocolVersion, protocolVersionEncoder } from "./protocolVersion.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { decodeVarLenType, varLenTypeEncoder } from "./codec/variableLength.js";
import { decodeUint16, uint16Encoder } from "./codec/number.js";
export const capabilitiesEncoder = contramapBufferEncoders([
    varLenTypeEncoder(protocolVersionEncoder),
    varLenTypeEncoder(ciphersuiteEncoder),
    varLenTypeEncoder(uint16Encoder),
    varLenTypeEncoder(uint16Encoder),
    varLenTypeEncoder(credentialTypeEncoder),
], (cap) => [cap.versions, cap.ciphersuites, cap.extensions, cap.proposals, cap.credentials]);
export const encodeCapabilities = encode(capabilitiesEncoder);
export const decodeCapabilities = mapDecoders([
    decodeVarLenType(decodeProtocolVersion),
    decodeVarLenType(decodeCiphersuite),
    decodeVarLenType(decodeUint16),
    decodeVarLenType(decodeUint16),
    decodeVarLenType(decodeCredentialType),
], (versions, ciphersuites, extensions, proposals, credentials) => ({
    versions,
    ciphersuites,
    extensions,
    proposals,
    credentials,
}));
//# sourceMappingURL=capabilities.js.map