export function mapDecoder(dec, f) {
    return (b, offset) => {
        const x = dec(b, offset);
        if (x !== undefined) {
            const [t, l] = x;
            return [f(t), l];
        }
    };
}
export function mapDecodersOption(decoders, f) {
    return (b, offset) => {
        const initial = mapDecoders(decoders, f)(b, offset);
        if (initial === undefined)
            return undefined;
        else {
            const [r, len] = initial;
            return r !== undefined ? [r, len] : undefined;
        }
    };
}
export function mapDecoders(decoders, f) {
    return (b, offset) => {
        const result = decoders.reduce((acc, decoder) => {
            if (!acc)
                return undefined;
            const decoded = decoder(b, acc.offset);
            if (!decoded)
                return undefined;
            const [value, length] = decoded;
            return {
                values: [...acc.values, value],
                offset: acc.offset + length,
                totalLength: acc.totalLength + length,
            };
        }, { values: [], offset, totalLength: 0 });
        if (!result)
            return;
        return [f(...result.values), result.totalLength];
    };
}
export function mapDecoderOption(dec, f) {
    return (b, offset) => {
        const x = dec(b, offset);
        if (x !== undefined) {
            const [t, l] = x;
            const u = f(t);
            return u !== undefined ? [u, l] : undefined;
        }
    };
}
export function flatMapDecoder(dec, f) {
    return flatMapDecoderAndMap(dec, f, (_t, u) => u);
}
export function orDecoder(decT, decU) {
    return (b, offset) => {
        const t = decT(b, offset);
        return t ? t : decU(b, offset);
    };
}
export function flatMapDecoderAndMap(dec, f, g) {
    return (b, offset) => {
        const decodedT = dec(b, offset);
        if (decodedT !== undefined) {
            const [t, len] = decodedT;
            const decoderU = f(t);
            const decodedU = decoderU(b, offset + len);
            if (decodedU !== undefined) {
                const [u, len2] = decodedU;
                return [g(t, u), len + len2];
            }
        }
    };
}
export function succeedDecoder(t) {
    return () => [t, 0];
}
export function failDecoder() {
    return () => undefined;
}
//# sourceMappingURL=tlsDecoder.js.map