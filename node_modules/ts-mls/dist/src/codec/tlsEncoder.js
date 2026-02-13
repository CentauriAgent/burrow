export function encode(enc) {
    return (t) => {
        const [len, write] = enc(t);
        const buf = new ArrayBuffer(len);
        write(0, buf);
        return new Uint8Array(buf);
    };
}
export function contramapBufferEncoder(enc, f) {
    return (u) => enc(f(u));
}
export function contramapBufferEncoders(encoders, toTuple) {
    return (value) => {
        const values = toTuple(value);
        let totalLength = 0;
        let writeTotal = (_offset, _buffer) => { };
        for (let i = 0; i < encoders.length; i++) {
            const [len, write] = encoders[i](values[i]);
            const oldFunc = writeTotal;
            const currentLen = totalLength;
            writeTotal = (offset, buffer) => {
                oldFunc(offset, buffer);
                write(offset + currentLen, buffer);
            };
            totalLength += len;
        }
        return [totalLength, writeTotal];
    };
}
export function composeBufferEncoders(encoders) {
    return (values) => contramapBufferEncoders(encoders, (t) => t)(values);
}
export const encVoid = [0, () => { }];
//# sourceMappingURL=tlsEncoder.js.map