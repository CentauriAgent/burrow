import { composeBufferEncoders, encode } from "../codec/tlsEncoder.js";
import { varLenDataEncoder } from "../codec/variableLength.js";
export async function signWithLabel(signKey, label, content, s) {
    return s.sign(signKey, encode(composeBufferEncoders([varLenDataEncoder, varLenDataEncoder]))([
        new TextEncoder().encode(`MLS 1.0 ${label}`),
        content,
    ]));
}
export async function verifyWithLabel(publicKey, label, content, signature, s) {
    return s.verify(publicKey, encode(composeBufferEncoders([varLenDataEncoder, varLenDataEncoder]))([
        new TextEncoder().encode(`MLS 1.0 ${label}`),
        content,
    ]), signature);
}
//# sourceMappingURL=signature.js.map