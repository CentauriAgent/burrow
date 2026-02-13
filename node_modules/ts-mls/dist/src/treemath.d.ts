import { Brand } from "./util/brand.js";
/** @public */
export type NodeIndex = Brand<number, "NodeIndex">;
/** @public */
export declare function toNodeIndex(n: number): NodeIndex;
/** @public */
export type LeafIndex = Brand<number, "LeafIndex">;
/** @public */
export declare function toLeafIndex(n: number): LeafIndex;
export declare function isLeaf(nodeIndex: NodeIndex): boolean;
export declare function leafToNodeIndex(leafIndex: LeafIndex): NodeIndex;
export declare function nodeToLeafIndex(nodeIndex: NodeIndex): LeafIndex;
export declare function leafWidth(nodeWidth: number): number;
export declare function nodeWidth(leafWidth: number): number;
export declare function rootFromNodeWidth(nodeWidth: number): NodeIndex;
export declare function root(leafWidth: number): NodeIndex;
export declare function left(nodeIndex: NodeIndex): NodeIndex;
export declare function right(nodeIndex: NodeIndex): NodeIndex;
export declare function parent(nodeIndex: NodeIndex, leafWidth: number): NodeIndex;
export declare function sibling(x: NodeIndex, leafWidth: number): NodeIndex;
export declare function directPath(nodeIndex: NodeIndex, leafWidth: number): NodeIndex[];
export declare function copath(nodeIndex: NodeIndex, leafWidth: number): NodeIndex[];
export declare function isAncestor(childNodeIndex: NodeIndex, ancestor: NodeIndex, nodeWidth: number): boolean;
