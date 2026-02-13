import { decodeOptional, optionalEncoder } from "./codec/optional.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenType, varLenTypeEncoder } from "./codec/variableLength.js";
import { decodeProposalOrRef, proposalOrRefEncoder } from "./proposalOrRefType.js";
import { decodeUpdatePath, updatePathEncoder } from "./updatePath.js";
export const commitEncoder = contramapBufferEncoders([varLenTypeEncoder(proposalOrRefEncoder), optionalEncoder(updatePathEncoder)], (commit) => [commit.proposals, commit.path]);
export const encodeCommit = encode(commitEncoder);
export const decodeCommit = mapDecoders([decodeVarLenType(decodeProposalOrRef), decodeOptional(decodeUpdatePath)], (proposals, path) => ({ proposals, path }));
//# sourceMappingURL=commit.js.map