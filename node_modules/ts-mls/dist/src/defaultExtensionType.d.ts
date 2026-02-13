import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export declare const defaultExtensionTypes: {
    readonly application_id: 1;
    readonly ratchet_tree: 2;
    readonly required_capabilities: 3;
    readonly external_pub: 4;
    readonly external_senders: 5;
};
/** @public */
export type DefaultExtensionTypeName = keyof typeof defaultExtensionTypes;
export type DefaultExtensionTypeValue = (typeof defaultExtensionTypes)[DefaultExtensionTypeName];
export declare const defaultExtensionTypeEncoder: BufferEncoder<DefaultExtensionTypeName>;
export declare const encodeDefaultExtensionType: Encoder<DefaultExtensionTypeName>;
export declare const decodeDefaultExtensionType: Decoder<DefaultExtensionTypeName>;
