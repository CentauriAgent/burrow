import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const protocolVersions = {
    mls10: 1,
};
export const protocolVersionEncoder = contramapBufferEncoder(uint16Encoder, (t) => protocolVersions[t]);
export const encodeProtocolVersion = encode(protocolVersionEncoder);
export const decodeProtocolVersion = mapDecoderOption(decodeUint16, enumNumberToKey(protocolVersions));
//# sourceMappingURL=protocolVersion.js.map