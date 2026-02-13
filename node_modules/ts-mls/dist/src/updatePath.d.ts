import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Hash } from "./crypto/hash.js";
import { PrivateKey } from "./crypto/hpke.js";
import { GroupContext } from "./groupContext.js";
import { LeafNodeCommit } from "./leafNode.js";
import { RatchetTree } from "./ratchetTree.js";
import { LeafIndex, NodeIndex } from "./treemath.js";
import { HPKECiphertext } from "./hpkeCiphertext.js";
/** @public */
export interface UpdatePathNode {
    hpkePublicKey: Uint8Array;
    encryptedPathSecret: HPKECiphertext[];
}
export declare const updatePathNodeEncoder: BufferEncoder<UpdatePathNode>;
export declare const encodeUpdatePathNode: Encoder<UpdatePathNode>;
export declare const decodeUpdatePathNode: Decoder<UpdatePathNode>;
/** @public */
export interface UpdatePath {
    leafNode: LeafNodeCommit;
    nodes: UpdatePathNode[];
}
export declare const updatePathEncoder: BufferEncoder<UpdatePath>;
export declare const encodeUpdatePath: Encoder<UpdatePath>;
export declare const decodeUpdatePath: Decoder<UpdatePath>;
export interface PathSecret {
    nodeIndex: number;
    secret: Uint8Array;
    sendTo: number[];
}
export declare function createUpdatePath(originalTree: RatchetTree, senderLeafIndex: LeafIndex, groupContext: GroupContext, signaturePrivateKey: Uint8Array, cs: CiphersuiteImpl): Promise<[RatchetTree, UpdatePath, PathSecret[], PrivateKey]>;
export declare function applyUpdatePath(tree: RatchetTree, senderLeafIndex: LeafIndex, path: UpdatePath, h: Hash, isExternal?: boolean): Promise<RatchetTree>;
export declare function firstCommonAncestor(tree: RatchetTree, leafIndex: LeafIndex, senderLeafIndex: LeafIndex): NodeIndex;
export declare function firstMatchAncestor(tree: RatchetTree, leafIndex: LeafIndex, senderLeafIndex: LeafIndex, path: UpdatePath): {
    nodeIndex: NodeIndex;
    resolution: NodeIndex[];
    updateNode: UpdatePathNode | undefined;
};
