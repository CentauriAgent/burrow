import { Kdf } from "./crypto/kdf.js";
import { RatchetTree } from "./ratchetTree.js";
import { NodeIndex } from "./treemath.js";
import { PathSecret } from "./updatePath.js";
/**
 * PathSecrets is a record with nodeIndex as keys and the path secret as values
 */
export type PathSecrets = Record<number, Uint8Array>;
export declare function pathToPathSecrets(pathSecrets: PathSecret[]): PathSecrets;
export declare function getCommitSecret(tree: RatchetTree, nodeIndex: NodeIndex, pathSecret: Uint8Array, kdf: Kdf): Promise<Uint8Array>;
export declare function pathToRoot(tree: RatchetTree, nodeIndex: NodeIndex, pathSecret: Uint8Array, kdf: Kdf): Promise<PathSecrets>;
