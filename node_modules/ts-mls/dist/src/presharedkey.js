import { decodeUint16, decodeUint64, decodeUint8, uint16Encoder, uint64Encoder, uint8Encoder } from "./codec/number.js";
import { flatMapDecoder, mapDecoder, mapDecoderOption, mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { expandWithLabel } from "./crypto/kdf.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
export const pskTypes = {
    external: 1,
    resumption: 2,
};
export const pskTypeEncoder = contramapBufferEncoder(uint8Encoder, (t) => pskTypes[t]);
export const encodePskType = encode(pskTypeEncoder);
export const decodePskType = mapDecoderOption(decodeUint8, enumNumberToKey(pskTypes));
/** @public */
export const resumptionPSKUsages = {
    application: 1,
    reinit: 2,
    branch: 3,
};
export const resumptionPSKUsageEncoder = contramapBufferEncoder(uint8Encoder, (u) => resumptionPSKUsages[u]);
export const encodeResumptionPSKUsage = encode(resumptionPSKUsageEncoder);
export const decodeResumptionPSKUsage = mapDecoderOption(decodeUint8, enumNumberToKey(resumptionPSKUsages));
const encodePskInfoExternal = contramapBufferEncoders([pskTypeEncoder, varLenDataEncoder], (i) => [i.psktype, i.pskId]);
const encodePskInfoResumption = contramapBufferEncoders([pskTypeEncoder, resumptionPSKUsageEncoder, varLenDataEncoder, uint64Encoder], (info) => [info.psktype, info.usage, info.pskGroupId, info.pskEpoch]);
const decodePskInfoResumption = mapDecoders([decodeResumptionPSKUsage, decodeVarLenData, decodeUint64], (usage, pskGroupId, pskEpoch) => {
    return { usage, pskGroupId, pskEpoch };
});
export const pskInfoEncoder = (info) => {
    switch (info.psktype) {
        case "external":
            return encodePskInfoExternal(info);
        case "resumption":
            return encodePskInfoResumption(info);
    }
};
export const encodePskInfo = encode(pskInfoEncoder);
export const decodePskInfo = flatMapDecoder(decodePskType, (psktype) => {
    switch (psktype) {
        case "external":
            return mapDecoder(decodeVarLenData, (pskId) => ({
                psktype,
                pskId,
            }));
        case "resumption":
            return mapDecoder(decodePskInfoResumption, (resumption) => ({
                psktype,
                ...resumption,
            }));
    }
});
export const pskIdEncoder = contramapBufferEncoders([pskInfoEncoder, varLenDataEncoder], (pskid) => [pskid, pskid.pskNonce]);
export const encodePskId = encode(pskIdEncoder);
export const decodePskId = mapDecoders([decodePskInfo, decodeVarLenData], (info, pskNonce) => ({ ...info, pskNonce }));
export const pskLabelEncoder = contramapBufferEncoders([pskIdEncoder, uint16Encoder, uint16Encoder], (label) => [label.id, label.index, label.count]);
export const encodePskLabel = encode(pskLabelEncoder);
export const decodePskLabel = mapDecoders([decodePskId, decodeUint16, decodeUint16], (id, index, count) => ({ id, index, count }));
export async function computePskSecret(psks, impl) {
    const zeroes = new Uint8Array(impl.kdf.size);
    return psks.reduce(async (acc, [curId, curPsk], index) => updatePskSecret(await acc, curId, curPsk, index, psks.length, impl), Promise.resolve(zeroes));
}
export async function updatePskSecret(secret, pskId, psk, index, count, impl) {
    const zeroes = new Uint8Array(impl.kdf.size);
    return impl.kdf.extract(await expandWithLabel(await impl.kdf.extract(zeroes, psk), "derived psk", encode(pskLabelEncoder)({ id: pskId, index, count }), impl.kdf.size, impl.kdf), secret);
}
//# sourceMappingURL=presharedkey.js.map