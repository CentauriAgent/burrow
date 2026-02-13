import { decodeUint8, uint8Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const contentTypes = {
    application: 1,
    proposal: 2,
    commit: 3,
};
export const contentTypeEncoder = contramapBufferEncoder(uint8Encoder, (t) => contentTypes[t]);
export const encodeContentType = encode(contentTypeEncoder);
export const decodeContentType = mapDecoderOption(decodeUint8, enumNumberToKey(contentTypes));
//# sourceMappingURL=contentType.js.map