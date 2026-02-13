import { toBufferSource } from "../../../util/byteArray.js";
export function makeHashImpl(sc, h) {
    return {
        async digest(data) {
            const result = await sc.digest(h, toBufferSource(data));
            return new Uint8Array(result);
        },
        async mac(key, data) {
            const result = await sc.sign("HMAC", await importMacKey(key, h), toBufferSource(data));
            return new Uint8Array(result);
        },
        async verifyMac(key, mac, data) {
            return sc.verify("HMAC", await importMacKey(key, h), toBufferSource(mac), toBufferSource(data));
        },
    };
}
function importMacKey(rawKey, h) {
    return crypto.subtle.importKey("raw", toBufferSource(rawKey), {
        name: "HMAC",
        hash: { name: h },
    }, false, ["sign", "verify"]);
}
//# sourceMappingURL=makeHashImpl.js.map