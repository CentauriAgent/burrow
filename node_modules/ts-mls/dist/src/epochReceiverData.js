import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders } from "./codec/tlsEncoder.js";
import { varLenDataEncoder, decodeVarLenData } from "./codec/variableLength.js";
import { groupContextEncoder, decodeGroupContext } from "./groupContext.js";
import { ratchetTreeEncoder, decodeRatchetTree } from "./ratchetTree.js";
import { secretTreeEncoder, decodeSecretTree } from "./secretTree.js";
export const epochReceiverDataEncoder = contramapBufferEncoders([varLenDataEncoder, secretTreeEncoder, ratchetTreeEncoder, varLenDataEncoder, groupContextEncoder], (erd) => [erd.resumptionPsk, erd.secretTree, erd.ratchetTree, erd.senderDataSecret, erd.groupContext]);
export const decodeEpochReceiverData = mapDecoders([decodeVarLenData, decodeSecretTree, decodeRatchetTree, decodeVarLenData, decodeGroupContext], (resumptionPsk, secretTree, ratchetTree, senderDataSecret, groupContext) => ({
    resumptionPsk,
    secretTree,
    ratchetTree,
    senderDataSecret,
    groupContext,
}));
//# sourceMappingURL=epochReceiverData.js.map