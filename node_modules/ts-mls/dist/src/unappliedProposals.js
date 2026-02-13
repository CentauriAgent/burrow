import { decodeUint32, uint32Encoder } from "./codec/number.js";
import { decodeOptional, optionalEncoder } from "./codec/optional.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders } from "./codec/tlsEncoder.js";
import { base64RecordEncoder, decodeBase64Record } from "./codec/variableLength.js";
import { decodeProposal, proposalEncoder } from "./proposal.js";
import { bytesToBase64 } from "./util/byteArray.js";
export const proposalWithSenderEncoder = contramapBufferEncoders([proposalEncoder, optionalEncoder(uint32Encoder)], (pws) => [pws.proposal, pws.senderLeafIndex]);
export const decodeProposalWithSender = mapDecoders([decodeProposal, decodeOptional(decodeUint32)], (proposal, senderLeafIndex) => ({
    proposal,
    senderLeafIndex,
}));
export const unappliedProposalsEncoder = base64RecordEncoder(proposalWithSenderEncoder);
export const decodeUnappliedProposals = decodeBase64Record(decodeProposalWithSender);
export function addUnappliedProposal(ref, proposals, proposal, senderLeafIndex) {
    const r = bytesToBase64(ref);
    return {
        ...proposals,
        [r]: { proposal, senderLeafIndex },
    };
}
//# sourceMappingURL=unappliedProposals.js.map