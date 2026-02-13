import { varLenDataEncoder } from "../codec/variableLength.js";
import { uint16Encoder, uint32Encoder } from "../codec/number.js";
import { composeBufferEncoders, encode } from "../codec/tlsEncoder.js";
export function expandWithLabel(secret, label, context, length, kdf) {
    return kdf.expand(secret, encode(composeBufferEncoders([uint16Encoder, varLenDataEncoder, varLenDataEncoder]))([
        length,
        new TextEncoder().encode(`MLS 1.0 ${label}`),
        context,
    ]), length);
}
export async function deriveSecret(secret, label, kdf) {
    return expandWithLabel(secret, label, new Uint8Array(), kdf.size, kdf);
}
export async function deriveTreeSecret(secret, label, generation, length, kdf) {
    return expandWithLabel(secret, label, encode(uint32Encoder)(generation), length, kdf);
}
//# sourceMappingURL=kdf.js.map