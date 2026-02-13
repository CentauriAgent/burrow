import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoders, orDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeDefaultExtensionType, defaultExtensionTypeEncoder, defaultExtensionTypes, } from "./defaultExtensionType.js";
import { constantTimeEqual } from "./util/constantTimeCompare.js";
export const extensionTypeEncoder = (t) => typeof t === "number" ? uint16Encoder(t) : defaultExtensionTypeEncoder(t);
export const encodeExtensionType = encode(extensionTypeEncoder);
export const decodeExtensionType = orDecoder(decodeDefaultExtensionType, decodeUint16);
export const extensionEncoder = contramapBufferEncoders([extensionTypeEncoder, varLenDataEncoder], (e) => [e.extensionType, e.extensionData]);
export const encodeExtension = encode(extensionEncoder);
export const decodeExtension = mapDecoders([decodeExtensionType, decodeVarLenData], (extensionType, extensionData) => ({ extensionType, extensionData }));
export function extensionEqual(a, b) {
    return a.extensionType === b.extensionType && constantTimeEqual(a.extensionData, b.extensionData);
}
export function extensionsEqual(a, b) {
    if (a.length !== b.length)
        return false;
    return a.every((val, i) => extensionEqual(val, b[i]));
}
export function extensionsSupportedByCapabilities(requiredExtensions, capabilities) {
    return requiredExtensions
        .filter((ex) => !isDefaultExtension(ex.extensionType))
        .every((ex) => capabilities.extensions.includes(extensionTypeToNumber(ex.extensionType)));
}
function isDefaultExtension(t) {
    return typeof t !== "number";
}
export function extensionTypeToNumber(t) {
    return typeof t === "number" ? t : defaultExtensionTypes[t];
}
//# sourceMappingURL=extension.js.map