import { decodeUint32, decodeUint64, decodeUint8, uint32Encoder, uint64Encoder, uint8Encoder } from "./codec/number.js";
import { flatMapDecoder, mapDecoder, mapDecoderOption, mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { contentTypeEncoder, decodeContentType } from "./contentType.js";
import { expandWithLabel } from "./crypto/kdf.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const senderTypes = {
    member: 1,
    external: 2,
    new_member_proposal: 3,
    new_member_commit: 4,
};
export const senderTypeEncoder = contramapBufferEncoder(uint8Encoder, (t) => senderTypes[t]);
export const encodeSenderType = encode(senderTypeEncoder);
export const decodeSenderType = mapDecoderOption(decodeUint8, enumNumberToKey(senderTypes));
export const senderEncoder = (s) => {
    switch (s.senderType) {
        case "member":
            return contramapBufferEncoders([senderTypeEncoder, uint32Encoder], (s) => [s.senderType, s.leafIndex])(s);
        case "external":
            return contramapBufferEncoders([senderTypeEncoder, uint32Encoder], (s) => [s.senderType, s.senderIndex])(s);
        case "new_member_proposal":
        case "new_member_commit":
            return senderTypeEncoder(s.senderType);
    }
};
export const encodeSender = encode(senderEncoder);
export const decodeSender = flatMapDecoder(decodeSenderType, (senderType) => {
    switch (senderType) {
        case "member":
            return mapDecoder(decodeUint32, (leafIndex) => ({
                senderType,
                leafIndex,
            }));
        case "external":
            return mapDecoder(decodeUint32, (senderIndex) => ({
                senderType,
                senderIndex,
            }));
        case "new_member_proposal":
            return mapDecoder(() => [undefined, 0], () => ({
                senderType,
            }));
        case "new_member_commit":
            return mapDecoder(() => [undefined, 0], () => ({
                senderType,
            }));
    }
});
export function getSenderLeafNodeIndex(sender) {
    return sender.senderType === "member" ? sender.leafIndex : undefined;
}
export const reuseGuardEncoder = (g) => [
    4,
    (offset, buffer) => {
        const view = new Uint8Array(buffer, offset, 4);
        view.set(g, 0);
    },
];
export const encodeReuseGuard = encode(reuseGuardEncoder);
export const decodeReuseGuard = (b, offset) => {
    return [b.subarray(offset, offset + 4), 4];
};
export const senderDataEncoder = contramapBufferEncoders([uint32Encoder, uint32Encoder, reuseGuardEncoder], (s) => [s.leafIndex, s.generation, s.reuseGuard]);
export const encodeSenderData = encode(senderDataEncoder);
export const decodeSenderData = mapDecoders([decodeUint32, decodeUint32, decodeReuseGuard], (leafIndex, generation, reuseGuard) => ({
    leafIndex,
    generation,
    reuseGuard,
}));
export const senderDataAADEncoder = contramapBufferEncoders([varLenDataEncoder, uint64Encoder, contentTypeEncoder], (aad) => [aad.groupId, aad.epoch, aad.contentType]);
export const encodeSenderDataAAD = encode(senderDataAADEncoder);
export const decodeSenderDataAAD = mapDecoders([decodeVarLenData, decodeUint64, decodeContentType], (groupId, epoch, contentType) => ({
    groupId,
    epoch,
    contentType,
}));
export function sampleCiphertext(cs, ciphertext) {
    return ciphertext.length < cs.kdf.size ? ciphertext : ciphertext.subarray(0, cs.kdf.size);
}
export async function expandSenderDataKey(cs, senderDataSecret, ciphertext) {
    const ciphertextSample = sampleCiphertext(cs, ciphertext);
    const keyLength = cs.hpke.keyLength;
    return await expandWithLabel(senderDataSecret, "key", ciphertextSample, keyLength, cs.kdf);
}
export async function expandSenderDataNonce(cs, senderDataSecret, ciphertext) {
    const ciphertextSample = sampleCiphertext(cs, ciphertext);
    const keyLength = cs.hpke.nonceLength;
    return await expandWithLabel(senderDataSecret, "nonce", ciphertextSample, keyLength, cs.kdf);
}
//# sourceMappingURL=sender.js.map