import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { DefaultExtensionTypeName } from "./defaultExtensionType.js";
/** @public */
export type ExtensionType = DefaultExtensionTypeName | number;
export declare const extensionTypeEncoder: BufferEncoder<ExtensionType>;
export declare const encodeExtensionType: Encoder<ExtensionType>;
export declare const decodeExtensionType: Decoder<ExtensionType>;
/** @public */
export interface Extension {
    extensionType: ExtensionType;
    extensionData: Uint8Array;
}
export declare const extensionEncoder: BufferEncoder<Extension>;
export declare const encodeExtension: Encoder<Extension>;
export declare const decodeExtension: Decoder<Extension>;
export declare function extensionEqual(a: Extension, b: Extension): boolean;
export declare function extensionsEqual(a: Extension[], b: Extension[]): boolean;
export declare function extensionsSupportedByCapabilities(requiredExtensions: Extension[], capabilities: {
    extensions: number[];
}): boolean;
export declare function extensionTypeToNumber(t: ExtensionType): number;
