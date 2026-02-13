import { uint64Encoder, decodeUint64 } from "./codec/number.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
export const lifetimeEncoder = contramapBufferEncoders([uint64Encoder, uint64Encoder], (lt) => [lt.notBefore, lt.notAfter]);
export const encodeLifetime = encode(lifetimeEncoder);
export const decodeLifetime = mapDecoders([decodeUint64, decodeUint64], (notBefore, notAfter) => ({
    notBefore,
    notAfter,
}));
/** @public */
export const defaultLifetime = {
    notBefore: 0n,
    notAfter: 9223372036854775807n,
};
//# sourceMappingURL=lifetime.js.map