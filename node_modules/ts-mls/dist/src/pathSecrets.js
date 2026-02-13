import { deriveSecret } from "./crypto/kdf.js";
import { InternalError } from "./mlsError.js";
import { findFirstNonBlankAncestor } from "./ratchetTree.js";
import { root, leafWidth } from "./treemath.js";
export function pathToPathSecrets(pathSecrets) {
    return pathSecrets.reduce((acc, cur) => ({
        ...acc,
        [cur.nodeIndex]: cur.secret,
    }), {});
}
export async function getCommitSecret(tree, nodeIndex, pathSecret, kdf) {
    const rootIndex = root(leafWidth(tree.length));
    const path = await pathToRoot(tree, nodeIndex, pathSecret, kdf);
    const rootSecret = path[rootIndex];
    if (rootSecret === undefined)
        throw new InternalError("Could not find secret for root");
    return deriveSecret(rootSecret, "path", kdf);
}
export async function pathToRoot(tree, nodeIndex, pathSecret, kdf) {
    const rootIndex = root(leafWidth(tree.length));
    let currentIndex = nodeIndex;
    const pathSecrets = { [nodeIndex]: pathSecret };
    while (currentIndex != rootIndex) {
        const nextIndex = findFirstNonBlankAncestor(tree, currentIndex);
        const nextSecret = await deriveSecret(pathSecrets[currentIndex], "path", kdf);
        pathSecrets[nextIndex] = nextSecret;
        currentIndex = nextIndex;
    }
    return pathSecrets;
}
//# sourceMappingURL=pathSecrets.js.map