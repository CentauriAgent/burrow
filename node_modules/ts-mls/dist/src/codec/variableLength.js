import { CodecError } from "../mlsError.js";
import { base64ToBytes, bytesToBase64 } from "../util/byteArray.js";
import { decodeUint64, uint64Encoder } from "./number.js";
import { mapDecoder, mapDecoders } from "./tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders } from "./tlsEncoder.js";
export const varLenDataEncoder = (data) => {
    const [len, write] = lengthEncoder(data.length);
    return [
        len + data.length,
        (offset, buffer) => {
            write(offset, buffer);
            const view = new Uint8Array(buffer);
            view.set(data, offset + len);
        },
    ];
};
export function lengthEncoder(len) {
    if (len < 64) {
        return [
            1,
            (offset, buffer) => {
                // 1-byte length: 00xxxxxx
                const view = new DataView(buffer);
                view.setUint8(offset, len & 0b00111111);
            },
        ];
    }
    else if (len < 16384) {
        return [
            2,
            (offset, buffer) => {
                // 2-byte length: 01xxxxxx xxxxxxxx
                const view = new DataView(buffer);
                view.setUint8(offset, ((len >> 8) & 0b00111111) | 0b01000000);
                view.setUint8(offset + 1, len & 0xff);
            },
        ];
    }
    else if (len < 0x40000000) {
        return [
            4,
            (offset, buffer) => {
                // 4-byte length: 10xxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
                const view = new DataView(buffer);
                view.setUint8(offset, ((len >> 24) & 0b00111111) | 0b10000000);
                view.setUint8(offset + 1, (len >> 16) & 0xff);
                view.setUint8(offset + 2, (len >> 8) & 0xff);
                view.setUint8(offset + 3, len & 0xff);
            },
        ];
    }
    else {
        throw new CodecError("Length too large to encode (max is 2^30 - 1)");
    }
}
export function determineLength(data, offset = 0) {
    if (offset >= data.length) {
        throw new CodecError("Offset beyond buffer");
    }
    const firstByte = data[offset];
    const prefix = firstByte >> 6;
    if (prefix === 0) {
        return { length: firstByte & 0b00111111, lengthFieldSize: 1 };
    }
    else if (prefix === 1) {
        if (offset + 2 > data.length)
            throw new CodecError("Incomplete 2-byte length");
        return { length: ((firstByte & 0b00111111) << 8) | data[offset + 1], lengthFieldSize: 2 };
    }
    else if (prefix === 2) {
        if (offset + 4 > data.length)
            throw new CodecError("Incomplete 4-byte length");
        return {
            length: ((firstByte & 0b00111111) << 24) |
                (data[offset + 1] << 16) |
                (data[offset + 2] << 8) |
                data[offset + 3],
            lengthFieldSize: 4,
        };
    }
    else {
        throw new CodecError("8-byte length not supported in this implementation");
    }
}
export const decodeVarLenData = (buf, offset) => {
    if (offset >= buf.length) {
        throw new CodecError("Offset beyond buffer");
    }
    const { length, lengthFieldSize } = determineLength(buf, offset);
    const totalBytes = lengthFieldSize + length;
    if (offset + totalBytes > buf.length) {
        throw new CodecError("Data length exceeds buffer");
    }
    const data = buf.subarray(offset + lengthFieldSize, offset + totalBytes);
    return [data, totalBytes];
};
export function varLenTypeEncoder(enc) {
    return (data) => {
        let totalLength = 0;
        let writeTotal = (_offset, _buffer) => { };
        for (let i = 0; i < data.length; i++) {
            const [len, write] = enc(data[i]);
            const oldFunc = writeTotal;
            const currentLen = totalLength;
            writeTotal = (offset, buffer) => {
                oldFunc(offset, buffer);
                write(offset + currentLen, buffer);
            };
            totalLength += len;
        }
        const [headerLength, writeLength] = lengthEncoder(totalLength);
        return [
            headerLength + totalLength,
            (offset, buffer) => {
                writeLength(offset, buffer);
                writeTotal(offset + headerLength, buffer);
            },
        ];
    };
}
export function decodeVarLenType(dec) {
    return (b, offset) => {
        const d = decodeVarLenData(b, offset);
        if (d === undefined)
            return;
        const [totalBytes, totalLength] = d;
        let cursor = 0;
        const result = [];
        while (cursor < totalBytes.length) {
            const item = dec(totalBytes, cursor);
            if (item === undefined)
                return undefined;
            const [value, len] = item;
            result.push(value);
            cursor += len;
        }
        return [result, totalLength];
    };
}
export function base64RecordEncoder(valueEncoder) {
    const entryEncoder = contramapBufferEncoders([contramapBufferEncoder(varLenDataEncoder, base64ToBytes), valueEncoder], ([key, value]) => [key, value]);
    return contramapBufferEncoders([varLenTypeEncoder(entryEncoder)], (record) => [Object.entries(record)]);
}
export function decodeBase64Record(decodeValue) {
    return mapDecoder(decodeVarLenType(mapDecoders([mapDecoder(decodeVarLenData, bytesToBase64), decodeValue], (key, value) => [key, value])), (entries) => {
        const record = {};
        for (const [key, value] of entries) {
            record[key] = value;
        }
        return record;
    });
}
export function numberRecordEncoder(numberEncoder, valueEncoder) {
    const entryEncoder = contramapBufferEncoders([numberEncoder, valueEncoder], ([key, value]) => [key, value]);
    return contramapBufferEncoder(varLenTypeEncoder(entryEncoder), (record) => Object.entries(record).map(([key, value]) => [Number(key), value]));
}
export function decodeNumberRecord(decodeNumber, decodeValue) {
    return mapDecoder(decodeVarLenType(mapDecoders([decodeNumber, decodeValue], (key, value) => [key, value])), (entries) => {
        const record = {};
        for (const [key, value] of entries) {
            record[key] = value;
        }
        return record;
    });
}
export function bigintMapEncoder(valueEncoder) {
    const entryEncoder = contramapBufferEncoders([uint64Encoder, valueEncoder], ([key, value]) => [key, value]);
    return contramapBufferEncoder(varLenTypeEncoder(entryEncoder), (map) => Array.from(map.entries()));
}
export function decodeBigintMap(decodeValue) {
    return mapDecoder(decodeVarLenType(mapDecoders([decodeUint64, decodeValue], (key, value) => [key, value])), (entries) => new Map(entries));
}
//# sourceMappingURL=variableLength.js.map