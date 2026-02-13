import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
export const wireformats = {
    mls_public_message: 1,
    mls_private_message: 2,
    mls_welcome: 3,
    mls_group_info: 4,
    mls_key_package: 5,
};
export const wireformatEncoder = (s) => contramapBufferEncoder(uint16Encoder, (t) => wireformats[t])(s);
export const encodeWireformat = encode(wireformatEncoder);
export const decodeWireformat = mapDecoderOption(decodeUint16, enumNumberToKey(wireformats));
//# sourceMappingURL=wireformat.js.map