import { ciphersuites } from "./crypto/ciphersuite.js";
import { greaseCapabilities, defaultGreaseConfig } from "./grease.js";
/** @public */
export function defaultCapabilities() {
    return greaseCapabilities(defaultGreaseConfig, {
        versions: ["mls10"],
        ciphersuites: Object.keys(ciphersuites),
        extensions: [],
        proposals: [],
        credentials: ["basic", "x509"],
    });
}
//# sourceMappingURL=defaultCapabilities.js.map