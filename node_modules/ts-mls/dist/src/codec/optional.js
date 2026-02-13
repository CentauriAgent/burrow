import { decodeUint8 } from "./number.js";
export function optionalEncoder(encodeT) {
    return (t) => {
        if (t) {
            const [len, write] = encodeT(t);
            return [
                len + 1,
                (offset, buffer) => {
                    const view = new DataView(buffer);
                    view.setUint8(offset, 0x1);
                    write(offset + 1, buffer);
                },
            ];
        }
        else {
            return [
                1,
                (offset, buffer) => {
                    const view = new DataView(buffer);
                    view.setUint8(offset, 0x0);
                },
            ];
        }
    };
}
export function decodeOptional(decodeT) {
    return (b, offset) => {
        const presenceOctet = decodeUint8(b, offset)?.[0];
        if (presenceOctet == 1) {
            const result = decodeT(b, offset + 1);
            return result === undefined ? undefined : [result[0], result[1] + 1];
        }
        else {
            return [undefined, 1];
        }
    };
}
//# sourceMappingURL=optional.js.map