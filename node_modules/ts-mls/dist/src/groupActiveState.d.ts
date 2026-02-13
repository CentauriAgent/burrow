import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder } from "./codec/tlsEncoder.js";
import { Reinit } from "./proposal.js";
/** @public */
export type GroupActiveState = {
    kind: "active";
} | {
    kind: "suspendedPendingReinit";
    reinit: Reinit;
} | {
    kind: "removedFromGroup";
};
export declare const groupActiveStateEncoder: BufferEncoder<GroupActiveState>;
export declare const decodeGroupActiveState: Decoder<GroupActiveState>;
