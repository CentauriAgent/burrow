import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Hash } from "./crypto/hash.js";
import { RatchetTree } from "./ratchetTree.js";
import { NodeIndex } from "./treemath.js";
export interface ParentHashInput {
    encryptionKey: Uint8Array;
    parentHash: Uint8Array;
    originalSiblingTreeHash: Uint8Array;
}
export declare const parentHashInputEncoder: BufferEncoder<ParentHashInput>;
export declare const encodeParentHashInput: Encoder<ParentHashInput>;
export declare const decodeParentHashInput: Decoder<ParentHashInput>;
export declare function verifyParentHashes(tree: RatchetTree, h: Hash): Promise<boolean>;
/**
 * Calculcates parent hash for a given node or leaf and returns the node index of the parent or undefined if the given node is the root node.
 */
export declare function calculateParentHash(tree: RatchetTree, nodeIndex: NodeIndex, h: Hash): Promise<[Uint8Array, NodeIndex | undefined]>;
