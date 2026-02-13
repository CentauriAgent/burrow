/** @public */
export const defaultPaddingConfig = { kind: "padUntilLength", padUntilLength: 256 };
export function byteLengthToPad(encodedLength, config) {
    if (config.kind === "alwaysPad")
        return config.paddingLength;
    else
        return encodedLength >= config.padUntilLength ? 0 : config.padUntilLength - encodedLength;
}
//# sourceMappingURL=paddingConfig.js.map