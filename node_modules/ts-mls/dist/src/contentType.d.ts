import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export declare const contentTypes: {
    readonly application: 1;
    readonly proposal: 2;
    readonly commit: 3;
};
/** @public */
export type ContentTypeName = keyof typeof contentTypes;
export type ContentTypeValue = (typeof contentTypes)[ContentTypeName];
export declare const contentTypeEncoder: BufferEncoder<ContentTypeName>;
export declare const encodeContentType: Encoder<ContentTypeName>;
export declare const decodeContentType: Decoder<ContentTypeName>;
