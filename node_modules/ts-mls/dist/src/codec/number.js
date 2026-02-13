import { encode } from "./tlsEncoder.js";
export const uint8Encoder = (n) => [
    1,
    (offset, buffer) => {
        const view = new DataView(buffer);
        view.setUint8(offset, n);
    },
];
export const encodeUint8 = encode(uint8Encoder);
export const decodeUint8 = (b, offset) => {
    const value = b.at(offset);
    return value !== undefined ? [value, 1] : undefined;
};
export const uint16Encoder = (n) => [
    2,
    (offset, buffer) => {
        const view = new DataView(buffer);
        view.setUint16(offset, n);
    },
];
export const encodeUint16 = encode(uint16Encoder);
export const decodeUint16 = (b, offset) => {
    const view = new DataView(b.buffer, b.byteOffset, b.byteLength);
    try {
        return [view.getUint16(offset), 2];
    }
    catch (e) {
        return undefined;
    }
};
export const uint32Encoder = (n) => [
    4,
    (offset, buffer) => {
        const view = new DataView(buffer);
        view.setUint32(offset, n);
    },
];
export const encodeUint32 = encode(uint32Encoder);
export const decodeUint32 = (b, offset) => {
    const view = new DataView(b.buffer, b.byteOffset, b.byteLength);
    try {
        return [view.getUint32(offset), 4];
    }
    catch (e) {
        return undefined;
    }
};
export const uint64Encoder = (n) => [
    8,
    (offset, buffer) => {
        const view = new DataView(buffer);
        view.setBigUint64(offset, n);
    },
];
export const encodeUint64 = encode(uint64Encoder);
export const decodeUint64 = (b, offset) => {
    const view = new DataView(b.buffer, b.byteOffset, b.byteLength);
    try {
        return [view.getBigUint64(offset), 8];
    }
    catch (e) {
        return undefined;
    }
};
//# sourceMappingURL=number.js.map