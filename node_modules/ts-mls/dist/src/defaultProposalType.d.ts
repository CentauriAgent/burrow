import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
/** @public */
export declare const defaultProposalTypes: {
    readonly add: 1;
    readonly update: 2;
    readonly remove: 3;
    readonly psk: 4;
    readonly reinit: 5;
    readonly external_init: 6;
    readonly group_context_extensions: 7;
};
/** @public */
export type DefaultProposalTypeName = keyof typeof defaultProposalTypes;
export type DefaultProposalTypeValue = (typeof defaultProposalTypes)[DefaultProposalTypeName];
export declare const defaultProposalTypeEncoder: BufferEncoder<DefaultProposalTypeName>;
export declare const encodeDefaultProposalType: Encoder<DefaultProposalTypeName>;
export declare const decodeDefaultProposalType: Decoder<DefaultProposalTypeName>;
