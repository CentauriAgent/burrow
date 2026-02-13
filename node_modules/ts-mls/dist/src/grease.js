export const greaseValues = [
    0x0a0a, 0x1a1a, 0x2a2a, 0x3a3a, 0x4a4a, 0x5a5a, 0x6a6a, 0x7a7a, 0x8a8a, 0x9a9a, 0xaaaa, 0xbaba, 0xcaca, 0xdada,
    0xeaea,
];
export const defaultGreaseConfig = {
    probabilityPerGreaseValue: 0.1,
};
export function grease(greaseConfig) {
    return greaseValues.filter(() => greaseConfig.probabilityPerGreaseValue > Math.random());
}
export function greaseCiphersuites(greaseConfig) {
    return grease(greaseConfig).map((n) => n.toString());
}
export function greaseCredentials(greaseConfig) {
    return grease(greaseConfig).map((n) => n.toString());
}
export function greaseExtensions(greaseConfig) {
    return grease(greaseConfig).map((n) => ({ extensionType: n, extensionData: new Uint8Array() }));
}
export function greaseCapabilities(config, capabilities) {
    return {
        ciphersuites: [...capabilities.ciphersuites, ...greaseCiphersuites(config)],
        credentials: [...capabilities.credentials, ...greaseCredentials(config)],
        extensions: [...capabilities.extensions, ...grease(config)],
        proposals: [...capabilities.proposals, ...grease(config)],
        versions: capabilities.versions,
    };
}
//# sourceMappingURL=grease.js.map