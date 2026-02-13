import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { ProposalOrRef } from "./proposalOrRefType.js";
import { UpdatePath } from "./updatePath.js";
/** @public */
export interface Commit {
    proposals: ProposalOrRef[];
    path: UpdatePath | undefined;
}
export declare const commitEncoder: BufferEncoder<Commit>;
export declare const encodeCommit: Encoder<Commit>;
export declare const decodeCommit: Decoder<Commit>;
