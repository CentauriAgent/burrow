import { HkdfSha256, HkdfSha384, HkdfSha512 } from "@hpke/core";
import { bytesToArrayBuffer } from "../../../util/byteArray.js";
export function makeKdfImpl(k) {
    return {
        async extract(salt, ikm) {
            const result = await k.extract(bytesToArrayBuffer(salt), bytesToArrayBuffer(ikm));
            return new Uint8Array(result);
        },
        async expand(prk, info, len) {
            const result = await k.expand(bytesToArrayBuffer(prk), bytesToArrayBuffer(info), len);
            return new Uint8Array(result);
        },
        size: k.hashSize,
    };
}
export function makeKdf(kdfAlg) {
    switch (kdfAlg) {
        case "HKDF-SHA256":
            return new HkdfSha256();
        case "HKDF-SHA384":
            return new HkdfSha384();
        case "HKDF-SHA512":
            return new HkdfSha512();
    }
}
//# sourceMappingURL=makeKdfImpl.js.map