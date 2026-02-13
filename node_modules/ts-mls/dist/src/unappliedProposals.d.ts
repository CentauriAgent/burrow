import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder } from "./codec/tlsEncoder.js";
import { Proposal } from "./proposal.js";
/** @public */
export interface ProposalWithSender {
    proposal: Proposal;
    senderLeafIndex: number | undefined;
}
export declare const proposalWithSenderEncoder: BufferEncoder<ProposalWithSender>;
export declare const decodeProposalWithSender: Decoder<ProposalWithSender>;
/** @public */
export type UnappliedProposals = Record<string, ProposalWithSender>;
export declare const unappliedProposalsEncoder: BufferEncoder<UnappliedProposals>;
export declare const decodeUnappliedProposals: Decoder<UnappliedProposals>;
export declare function addUnappliedProposal(ref: Uint8Array, proposals: UnappliedProposals, proposal: Proposal, senderLeafIndex: number | undefined): UnappliedProposals;
