import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const defaultProposalTypes = {
    add: 1,
    update: 2,
    remove: 3,
    psk: 4,
    reinit: 5,
    external_init: 6,
    group_context_extensions: 7,
};
export const defaultProposalTypeEncoder = contramapBufferEncoder(uint16Encoder, (n) => defaultProposalTypes[n]);
export const encodeDefaultProposalType = encode(defaultProposalTypeEncoder);
export const decodeDefaultProposalType = mapDecoderOption(decodeUint16, enumNumberToKey(defaultProposalTypes));
//# sourceMappingURL=defaultProposalType.js.map