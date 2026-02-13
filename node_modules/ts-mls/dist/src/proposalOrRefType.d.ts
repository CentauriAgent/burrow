import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Proposal } from "./proposal.js";
declare const proposalOrRefTypes: {
    readonly proposal: 1;
    readonly reference: 2;
};
export type ProposalOrRefTypeName = keyof typeof proposalOrRefTypes;
export type ProposalOrRefTypeValue = (typeof proposalOrRefTypes)[ProposalOrRefTypeName];
export declare const proposalOrRefTypeEncoder: BufferEncoder<ProposalOrRefTypeName>;
export declare const encodeProposalOrRefType: Encoder<ProposalOrRefTypeName>;
export declare const decodeProposalOrRefType: Decoder<ProposalOrRefTypeName>;
/** @public */
export interface ProposalOrRefProposal {
    proposalOrRefType: "proposal";
    proposal: Proposal;
}
/** @public */
export interface ProposalOrRefProposalRef {
    proposalOrRefType: "reference";
    reference: Uint8Array;
}
/** @public */
export type ProposalOrRef = ProposalOrRefProposal | ProposalOrRefProposalRef;
export declare const proposalOrRefProposalEncoder: BufferEncoder<ProposalOrRefProposal>;
export declare const encodeProposalOrRefProposal: Encoder<ProposalOrRefProposal>;
export declare const proposalOrRefProposalRefEncoder: BufferEncoder<ProposalOrRefProposalRef>;
export declare const encodeProposalOrRefProposalRef: Encoder<ProposalOrRefProposalRef>;
export declare const proposalOrRefEncoder: BufferEncoder<ProposalOrRef>;
export declare const encodeProposalOrRef: Encoder<ProposalOrRef>;
export declare const decodeProposalOrRef: Decoder<ProposalOrRef>;
export {};
