import { uint32Encoder, decodeUint32 } from "./codec/number.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { varLenDataEncoder, varLenTypeEncoder, decodeVarLenData, decodeVarLenType } from "./codec/variableLength.js";
export const parentNodeEncoder = contramapBufferEncoders([varLenDataEncoder, varLenDataEncoder, varLenTypeEncoder(uint32Encoder)], (node) => [node.hpkePublicKey, node.parentHash, node.unmergedLeaves]);
export const encodeParentNode = encode(parentNodeEncoder);
export const decodeParentNode = mapDecoders([decodeVarLenData, decodeVarLenData, decodeVarLenType(decodeUint32)], (hpkePublicKey, parentHash, unmergedLeaves) => ({
    hpkePublicKey,
    parentHash,
    unmergedLeaves,
}));
//# sourceMappingURL=parentNode.js.map