/** @public */
export type PaddingConfig = {
    kind: "padUntilLength";
    padUntilLength: number;
} | {
    kind: "alwaysPad";
    paddingLength: number;
};
/** @public */
export declare const defaultPaddingConfig: PaddingConfig;
export declare function byteLengthToPad(encodedLength: number, config: PaddingConfig): number;
