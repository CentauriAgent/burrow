import { decodeUint32, uint32Encoder } from "./codec/number.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { deriveSecret } from "./crypto/kdf.js";
import { signWithLabel, verifyWithLabel } from "./crypto/signature.js";
import { decodeExtension, extensionEncoder } from "./extension.js";
import { decodeGroupContext, groupContextEncoder, extractEpochSecret } from "./groupContext.js";
import { CodecError } from "./mlsError.js";
import { decodeRatchetTree } from "./ratchetTree.js";
export const groupInfoTBSEncoder = contramapBufferEncoders([groupContextEncoder, varLenTypeEncoder(extensionEncoder), varLenDataEncoder, uint32Encoder], (g) => [g.groupContext, g.extensions, g.confirmationTag, g.signer]);
export const encodeGroupInfoTBS = encode(groupInfoTBSEncoder);
export const decodeGroupInfoTBS = mapDecoders([decodeGroupContext, decodeVarLenType(decodeExtension), decodeVarLenData, decodeUint32], (groupContext, extensions, confirmationTag, signer) => ({
    groupContext,
    extensions,
    confirmationTag,
    signer,
}));
export const groupInfoEncoder = contramapBufferEncoders([groupInfoTBSEncoder, varLenDataEncoder], (g) => [g, g.signature]);
export const encodeGroupInfo = encode(groupInfoEncoder);
export const decodeGroupInfo = mapDecoders([decodeGroupInfoTBS, decodeVarLenData], (tbs, signature) => ({
    ...tbs,
    signature,
}));
export function ratchetTreeFromExtension(info) {
    const treeExtension = info.extensions.find((ex) => ex.extensionType === "ratchet_tree");
    if (treeExtension !== undefined) {
        const tree = decodeRatchetTree(treeExtension.extensionData, 0);
        if (tree === undefined)
            throw new CodecError("Could not decode RatchetTree");
        return tree[0];
    }
}
export async function signGroupInfo(tbs, privateKey, s) {
    const signature = await signWithLabel(privateKey, "GroupInfoTBS", encode(groupInfoTBSEncoder)(tbs), s);
    return { ...tbs, signature };
}
export function verifyGroupInfoSignature(gi, publicKey, s) {
    return verifyWithLabel(publicKey, "GroupInfoTBS", encode(groupInfoTBSEncoder)(gi), gi.signature, s);
}
export async function verifyGroupInfoConfirmationTag(gi, joinerSecret, pskSecret, cs) {
    const epochSecret = await extractEpochSecret(gi.groupContext, joinerSecret, cs.kdf, pskSecret);
    const key = await deriveSecret(epochSecret, "confirm", cs.kdf);
    return cs.hash.verifyMac(key, gi.confirmationTag, gi.groupContext.confirmedTranscriptHash);
}
export async function extractWelcomeSecret(joinerSecret, pskSecret, kdf) {
    return deriveSecret(await kdf.extract(joinerSecret, pskSecret), "welcome", kdf);
}
//# sourceMappingURL=groupInfo.js.map