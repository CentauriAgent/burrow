import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Decoder } from "./codec/tlsDecoder.js";
import { ParentNode } from "./parentNode.js";
import { LeafIndex, NodeIndex } from "./treemath.js";
import { LeafNode } from "./leafNode.js";
/** @public */
export type Node = NodeParent | NodeLeaf;
/** @public */
export type NodeParent = {
    nodeType: "parent";
    parent: ParentNode;
};
/** @public */
export type NodeLeaf = {
    nodeType: "leaf";
    leaf: LeafNode;
};
export declare const nodeEncoder: BufferEncoder<Node>;
export declare const encodeNode: Encoder<Node>;
export declare const decodeNode: Decoder<Node>;
export declare function getHpkePublicKey(n: Node): Uint8Array;
/** @public */
export type RatchetTree = (Node | undefined)[];
export declare function extendRatchetTree(tree: RatchetTree): RatchetTree;
/**
 * If the tree has 2d leaves, then it has 2d+1 - 1 nodes.
 * The ratchet_tree vector logically has this number of entries, but the sender MUST NOT include blank nodes after the last non-blank node.
 * The receiver MUST check that the last node in ratchet_tree is non-blank, and then extend the tree to the right until it has a length of the form 2d+1 - 1, adding the minimum number of blank values possible.
 * (Obviously, this may be done "virtually", by synthesizing blank nodes when required, as opposed to actually changing the structure in memory.)
 */
export declare function stripBlankNodes(tree: RatchetTree): RatchetTree;
export declare const ratchetTreeEncoder: BufferEncoder<RatchetTree>;
export declare const encodeRatchetTree: Encoder<RatchetTree>;
export declare const decodeRatchetTree: Decoder<RatchetTree>;
export declare function findBlankLeafNodeIndex(tree: RatchetTree): NodeIndex | undefined;
export declare function findBlankLeafNodeIndexOrExtend(tree: RatchetTree): NodeIndex;
export declare function extendTree(tree: RatchetTree, leafNode: LeafNode): [RatchetTree, NodeIndex];
export declare function addLeafNode(tree: RatchetTree, leafNode: LeafNode): [RatchetTree, NodeIndex];
export declare function updateLeafNode(tree: RatchetTree, leafNode: LeafNode, leafIndex: LeafIndex): RatchetTree;
export declare function removeLeafNode(tree: RatchetTree, removedLeafIndex: LeafIndex): RatchetTree;
export declare function resolution(tree: (Node | undefined)[], nodeIndex: NodeIndex): NodeIndex[];
export declare function filteredDirectPath(leafIndex: LeafIndex, tree: RatchetTree): NodeIndex[];
export declare function filteredDirectPathAndCopathResolution(leafIndex: LeafIndex, tree: RatchetTree): {
    resolution: NodeIndex[];
    nodeIndex: NodeIndex;
}[];
export declare function removeLeaves(tree: RatchetTree, leafIndices: LeafIndex[]): RatchetTree;
export declare function traverseToRoot<T>(tree: RatchetTree, leafIndex: LeafIndex, f: (nodeIndex: NodeIndex, node: ParentNode) => T | undefined): [T, NodeIndex] | undefined;
export declare function findFirstNonBlankAncestor(tree: RatchetTree, nodeIndex: NodeIndex): NodeIndex;
export declare function findLeafIndex(tree: RatchetTree, leaf: LeafNode): LeafIndex | undefined;
export declare function getCredentialFromLeafIndex(ratchetTree: RatchetTree, leafIndex: LeafIndex): import("./credential.js").Credential;
export declare function getSignaturePublicKeyFromLeafIndex(ratchetTree: RatchetTree, leafIndex: LeafIndex): Uint8Array;
