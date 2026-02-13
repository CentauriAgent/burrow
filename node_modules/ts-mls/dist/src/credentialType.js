import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { openEnumNumberEncoder, openEnumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const credentialTypes = {
    basic: 1,
    x509: 2,
};
export const credentialTypeEncoder = contramapBufferEncoder(uint16Encoder, openEnumNumberEncoder(credentialTypes));
export const encodeCredentialType = encode(credentialTypeEncoder);
export const decodeCredentialType = mapDecoderOption(decodeUint16, openEnumNumberToKey(credentialTypes));
//# sourceMappingURL=credentialType.js.map