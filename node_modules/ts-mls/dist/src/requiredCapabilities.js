import { credentialTypeEncoder, decodeCredentialType } from "./credentialType.js";
import { varLenTypeEncoder, decodeVarLenType } from "./codec/variableLength.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { decodeUint16, uint16Encoder } from "./codec/number.js";
export const requiredCapabilitiesEncoder = contramapBufferEncoders([varLenTypeEncoder(uint16Encoder), varLenTypeEncoder(uint16Encoder), varLenTypeEncoder(credentialTypeEncoder)], (rc) => [rc.extensionTypes, rc.proposalTypes, rc.credentialTypes]);
/** @public */
export const encodeRequiredCapabilities = encode(requiredCapabilitiesEncoder);
/** @public */
export const decodeRequiredCapabilities = mapDecoders([decodeVarLenType(decodeUint16), decodeVarLenType(decodeUint16), decodeVarLenType(decodeCredentialType)], (extensionTypes, proposalTypes, credentialTypes) => ({ extensionTypes, proposalTypes, credentialTypes }));
//# sourceMappingURL=requiredCapabilities.js.map