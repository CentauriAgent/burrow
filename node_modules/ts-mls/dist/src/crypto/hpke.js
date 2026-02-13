import { varLenDataEncoder } from "../codec/variableLength.js";
import { composeBufferEncoders, encode } from "../codec/tlsEncoder.js";
export function encryptWithLabel(publicKey, label, context, plaintext, hpke) {
    return hpke.seal(publicKey, plaintext, encode(composeBufferEncoders([varLenDataEncoder, varLenDataEncoder]))([
        new TextEncoder().encode(`MLS 1.0 ${label}`),
        context,
    ]), new Uint8Array());
}
export function decryptWithLabel(privateKey, label, context, kemOutput, ciphertext, hpke) {
    return hpke.open(privateKey, kemOutput, ciphertext, encode(composeBufferEncoders([varLenDataEncoder, varLenDataEncoder]))([
        new TextEncoder().encode(`MLS 1.0 ${label}`),
        context,
    ]));
}
//# sourceMappingURL=hpke.js.map