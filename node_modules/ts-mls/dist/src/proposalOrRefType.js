import { decodeUint8, uint8Encoder } from "./codec/number.js";
import { flatMapDecoder, mapDecoder, mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeProposal, proposalEncoder } from "./proposal.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
const proposalOrRefTypes = {
    proposal: 1,
    reference: 2,
};
export const proposalOrRefTypeEncoder = contramapBufferEncoder(uint8Encoder, (t) => proposalOrRefTypes[t]);
export const encodeProposalOrRefType = encode(proposalOrRefTypeEncoder);
export const decodeProposalOrRefType = mapDecoderOption(decodeUint8, enumNumberToKey(proposalOrRefTypes));
export const proposalOrRefProposalEncoder = contramapBufferEncoders([proposalOrRefTypeEncoder, proposalEncoder], (p) => [p.proposalOrRefType, p.proposal]);
export const encodeProposalOrRefProposal = encode(proposalOrRefProposalEncoder);
export const proposalOrRefProposalRefEncoder = contramapBufferEncoders([proposalOrRefTypeEncoder, varLenDataEncoder], (r) => [r.proposalOrRefType, r.reference]);
export const encodeProposalOrRefProposalRef = encode(proposalOrRefProposalRefEncoder);
export const proposalOrRefEncoder = (input) => {
    switch (input.proposalOrRefType) {
        case "proposal":
            return proposalOrRefProposalEncoder(input);
        case "reference":
            return proposalOrRefProposalRefEncoder(input);
    }
};
export const encodeProposalOrRef = encode(proposalOrRefEncoder);
export const decodeProposalOrRef = flatMapDecoder(decodeProposalOrRefType, (proposalOrRefType) => {
    switch (proposalOrRefType) {
        case "proposal":
            return mapDecoder(decodeProposal, (proposal) => ({ proposalOrRefType, proposal }));
        case "reference":
            return mapDecoder(decodeVarLenData, (reference) => ({ proposalOrRefType, reference }));
    }
});
//# sourceMappingURL=proposalOrRefType.js.map