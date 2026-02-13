import { NotSupportedError } from "@hpke/common";
export function emitNotSupported() {
    return new Promise((_resolve, reject) => {
        reject(new NotSupportedError("Not supported"));
    });
}
