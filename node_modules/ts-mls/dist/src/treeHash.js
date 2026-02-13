import { uint32Encoder, decodeUint32 } from "./codec/number.js";
import { optionalEncoder, decodeOptional } from "./codec/optional.js";
import { mapDecoders, flatMapDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { varLenDataEncoder, decodeVarLenData } from "./codec/variableLength.js";
import { leafNodeEncoder, decodeLeafNode } from "./leafNode.js";
import { InternalError } from "./mlsError.js";
import { nodeTypeEncoder, decodeNodeType } from "./nodeType.js";
import { parentNodeEncoder, decodeParentNode } from "./parentNode.js";
import { rootFromNodeWidth, isLeaf, nodeToLeafIndex, left, right } from "./treemath.js";
export const leafNodeHashInputEncoder = contramapBufferEncoders([nodeTypeEncoder, uint32Encoder, optionalEncoder(leafNodeEncoder)], (input) => [input.nodeType, input.leafIndex, input.leafNode]);
export const encodeLeafNodeHashInput = encode(leafNodeHashInputEncoder);
export const decodeLeafNodeHashInput = mapDecoders([decodeUint32, decodeOptional(decodeLeafNode)], (leafIndex, leafNode) => ({
    nodeType: "leaf",
    leafIndex,
    leafNode,
}));
export const parentNodeHashInputEncoder = contramapBufferEncoders([nodeTypeEncoder, optionalEncoder(parentNodeEncoder), varLenDataEncoder, varLenDataEncoder], (input) => [input.nodeType, input.parentNode, input.leftHash, input.rightHash]);
export const encodeParentNodeHashInput = encode(parentNodeHashInputEncoder);
export const decodeParentNodeHashInput = mapDecoders([decodeOptional(decodeParentNode), decodeVarLenData, decodeVarLenData], (parentNode, leftHash, rightHash) => ({
    nodeType: "parent",
    parentNode,
    leftHash,
    rightHash,
}));
export const treeHashInputEncoder = (input) => {
    switch (input.nodeType) {
        case "leaf":
            return leafNodeHashInputEncoder(input);
        case "parent":
            return parentNodeHashInputEncoder(input);
    }
};
export const encodeTreeHashInput = encode(treeHashInputEncoder);
export const decodeTreeHashInput = flatMapDecoder(decodeNodeType, (nodeType) => {
    switch (nodeType) {
        case "leaf":
            return decodeLeafNodeHashInput;
        case "parent":
            return decodeParentNodeHashInput;
    }
});
export async function treeHashRoot(tree, h) {
    return treeHash(tree, rootFromNodeWidth(tree.length), h);
}
export async function treeHash(tree, subtreeIndex, h) {
    if (isLeaf(subtreeIndex)) {
        const leafNode = tree[subtreeIndex];
        if (leafNode?.nodeType === "parent")
            throw new InternalError("Somehow found parent node in leaf position");
        const input = encode(leafNodeHashInputEncoder)({
            nodeType: "leaf",
            leafIndex: nodeToLeafIndex(subtreeIndex),
            leafNode: leafNode?.leaf,
        });
        return await h.digest(input);
    }
    else {
        const parentNode = tree[subtreeIndex];
        if (parentNode?.nodeType === "leaf")
            throw new InternalError("Somehow found leaf node in parent position");
        const leftHash = await treeHash(tree, left(subtreeIndex), h);
        const rightHash = await treeHash(tree, right(subtreeIndex), h);
        const input = {
            nodeType: "parent",
            parentNode: parentNode?.parent,
            leftHash: leftHash,
            rightHash: rightHash,
        };
        return await h.digest(encode(parentNodeHashInputEncoder)(input));
    }
}
//# sourceMappingURL=treeHash.js.map