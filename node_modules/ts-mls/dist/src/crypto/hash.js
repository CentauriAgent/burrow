import { composeBufferEncoders, encode } from "../codec/tlsEncoder.js";
import { varLenDataEncoder } from "../codec/variableLength.js";
export function refhash(label, value, h) {
    return h.digest(encodeRefHash(label, value));
}
function encodeRefHash(label, value) {
    const labelBytes = new TextEncoder().encode(label);
    const enc = composeBufferEncoders([varLenDataEncoder, varLenDataEncoder]);
    return encode(enc)([labelBytes, value]);
}
//# sourceMappingURL=hash.js.map