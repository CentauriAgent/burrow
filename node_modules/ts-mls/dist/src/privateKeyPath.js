import { decodeUint32, uint32Encoder } from "./codec/number.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders } from "./codec/tlsEncoder.js";
import { decodeNumberRecord, decodeVarLenData, numberRecordEncoder, varLenDataEncoder } from "./codec/variableLength.js";
import { deriveSecret } from "./crypto/kdf.js";
import { leafToNodeIndex, toLeafIndex } from "./treemath.js";
export const privateKeyPathEncoder = contramapBufferEncoders([uint32Encoder, numberRecordEncoder(uint32Encoder, varLenDataEncoder)], (pkp) => [pkp.leafIndex, pkp.privateKeys]);
export const decodePrivateKeyPath = mapDecoders([decodeUint32, decodeNumberRecord(decodeUint32, decodeVarLenData)], (leafIndex, privateKeys) => ({
    leafIndex,
    privateKeys,
}));
/**
 * Merges PrivateKeyPaths, BEWARE, if there is a conflict, this function will prioritize the second `b` parameter
 */
export function mergePrivateKeyPaths(a, b) {
    return { ...a, privateKeys: { ...a.privateKeys, ...b.privateKeys } };
}
export function updateLeafKey(path, newKey) {
    return { ...path, privateKeys: { ...path.privateKeys, [leafToNodeIndex(toLeafIndex(path.leafIndex))]: newKey } };
}
export async function toPrivateKeyPath(pathSecrets, leafIndex, cs) {
    const asArray = await Promise.all(Object.entries(pathSecrets).map(async ([nodeIndex, pathSecret]) => {
        const nodeSecret = await deriveSecret(pathSecret, "node", cs.kdf);
        const { privateKey } = await cs.hpke.deriveKeyPair(nodeSecret);
        return [Number(nodeIndex), await cs.hpke.exportPrivateKey(privateKey)];
    }));
    const privateKeys = Object.fromEntries(asArray);
    return { leafIndex, privateKeys };
}
//# sourceMappingURL=privateKeyPath.js.map