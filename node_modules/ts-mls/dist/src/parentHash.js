import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { InternalError } from "./mlsError.js";
import { findFirstNonBlankAncestor, removeLeaves } from "./ratchetTree.js";
import { treeHash } from "./treeHash.js";
import { isLeaf, leafWidth, left, right, root, toNodeIndex } from "./treemath.js";
import { constantTimeEqual } from "./util/constantTimeCompare.js";
export const parentHashInputEncoder = contramapBufferEncoders([varLenDataEncoder, varLenDataEncoder, varLenDataEncoder], (i) => [i.encryptionKey, i.parentHash, i.originalSiblingTreeHash]);
export const encodeParentHashInput = encode(parentHashInputEncoder);
export const decodeParentHashInput = mapDecoders([decodeVarLenData, decodeVarLenData, decodeVarLenData], (encryptionKey, parentHash, originalSiblingTreeHash) => ({
    encryptionKey,
    parentHash,
    originalSiblingTreeHash,
}));
function validateParentHashCoverage(parentIndices, coverage) {
    for (const index of parentIndices) {
        if ((coverage[index] ?? 0) !== 1) {
            return false;
        }
    }
    return true;
}
export async function verifyParentHashes(tree, h) {
    const parentNodes = tree.reduce((acc, cur, index) => {
        if (cur !== undefined && cur.nodeType === "parent") {
            return [...acc, index];
        }
        else
            return acc;
    }, []);
    if (parentNodes.length === 0)
        return true;
    const coverage = await parentHashCoverage(tree, h);
    return validateParentHashCoverage(parentNodes, coverage);
}
/**
 * Traverse tree from bottom up, verifying that all non-blank parent nodes are covered by exactly one chain
 */
function parentHashCoverage(tree, h) {
    return tree.reduce(async (acc, node, nodeIndex) => {
        let currentIndex = toNodeIndex(nodeIndex);
        if (!isLeaf(currentIndex) || node === undefined)
            return acc;
        let updated = { ...(await acc) };
        const rootIndex = root(leafWidth(tree.length));
        while (currentIndex !== rootIndex) {
            const currentNode = tree[currentIndex];
            // skip blank nodes
            if (currentNode === undefined) {
                continue;
            }
            // parentHashNodeIndex is the node index where the nearest non blank ancestor was
            const [parentHash, parentHashNodeIndex] = await calculateParentHash(tree, currentIndex, h);
            if (parentHashNodeIndex === undefined) {
                throw new InternalError("Reached root before completing parent hash coeverage");
            }
            const expectedParentHash = getParentHash(currentNode);
            if (expectedParentHash !== undefined && constantTimeEqual(parentHash, expectedParentHash)) {
                const newCount = (updated[parentHashNodeIndex] ?? 0) + 1;
                updated = { ...updated, [parentHashNodeIndex]: newCount };
            }
            else {
                // skip to next leaf
                break;
            }
            currentIndex = parentHashNodeIndex;
        }
        return updated;
    }, Promise.resolve({}));
}
function getParentHash(node) {
    if (node.nodeType === "parent")
        return node.parent.parentHash;
    else if (node.leaf.leafNodeSource === "commit")
        return node.leaf.parentHash;
}
/**
 * Calculcates parent hash for a given node or leaf and returns the node index of the parent or undefined if the given node is the root node.
 */
export async function calculateParentHash(tree, nodeIndex, h) {
    const rootIndex = root(leafWidth(tree.length));
    if (nodeIndex === rootIndex) {
        return [new Uint8Array(), undefined];
    }
    const parentNodeIndex = findFirstNonBlankAncestor(tree, nodeIndex);
    const parentNode = tree[parentNodeIndex];
    if (parentNodeIndex === rootIndex && parentNode === undefined) {
        return [new Uint8Array(), parentNodeIndex];
    }
    const siblingIndex = nodeIndex < parentNodeIndex ? right(parentNodeIndex) : left(parentNodeIndex);
    if (parentNode === undefined || parentNode.nodeType === "leaf")
        throw new InternalError("Expected non-blank parent Node");
    const removedUnmerged = removeLeaves(tree, parentNode.parent.unmergedLeaves);
    const originalSiblingTreeHash = await treeHash(removedUnmerged, siblingIndex, h);
    const input = {
        encryptionKey: parentNode.parent.hpkePublicKey,
        parentHash: parentNode.parent.parentHash,
        originalSiblingTreeHash,
    };
    return [await h.digest(encode(parentHashInputEncoder)(input)), parentNodeIndex];
}
//# sourceMappingURL=parentHash.js.map