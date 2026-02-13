import { InternalError } from "./mlsError.js";
/** @public */
export function toNodeIndex(n) {
    return n;
}
/** @public */
export function toLeafIndex(n) {
    return n;
}
function log2(x) {
    if (x === 0)
        return 0;
    let k = 0;
    while (x >> k > 0) {
        k++;
    }
    return k - 1;
}
function level(nodeIndex) {
    if ((nodeIndex & 0x01) === 0)
        return 0;
    let k = 0;
    while (((nodeIndex >> k) & 0x01) === 1) {
        k++;
    }
    return k;
}
export function isLeaf(nodeIndex) {
    return nodeIndex % 2 == 0;
}
export function leafToNodeIndex(leafIndex) {
    return toNodeIndex(leafIndex * 2);
}
export function nodeToLeafIndex(nodeIndex) {
    return toLeafIndex(nodeIndex / 2);
}
export function leafWidth(nodeWidth) {
    return nodeWidth == 0 ? 0 : (nodeWidth - 1) / 2 + 1;
}
export function nodeWidth(leafWidth) {
    return leafWidth === 0 ? 0 : 2 * (leafWidth - 1) + 1;
}
export function rootFromNodeWidth(nodeWidth) {
    return toNodeIndex((1 << log2(nodeWidth)) - 1);
}
export function root(leafWidth) {
    const w = nodeWidth(leafWidth);
    return rootFromNodeWidth(w);
}
export function left(nodeIndex) {
    const k = level(nodeIndex);
    if (k === 0)
        throw new InternalError("leaf node has no children");
    return toNodeIndex(nodeIndex ^ (0x01 << (k - 1)));
}
export function right(nodeIndex) {
    const k = level(nodeIndex);
    if (k === 0)
        throw new InternalError("leaf node has no children");
    return toNodeIndex(nodeIndex ^ (0x03 << (k - 1)));
}
export function parent(nodeIndex, leafWidth) {
    if (nodeIndex === root(leafWidth))
        throw new InternalError("root node has no parent");
    const k = level(nodeIndex);
    const b = (nodeIndex >> (k + 1)) & 0x01;
    return toNodeIndex((nodeIndex | (1 << k)) ^ (b << (k + 1)));
}
export function sibling(x, leafWidth) {
    const p = parent(x, leafWidth);
    return x < p ? right(p) : left(p);
}
export function directPath(nodeIndex, leafWidth) {
    const r = root(leafWidth);
    if (nodeIndex === r)
        return [];
    const d = [];
    while (nodeIndex !== r) {
        nodeIndex = parent(nodeIndex, leafWidth);
        d.push(nodeIndex);
    }
    return d;
}
export function copath(nodeIndex, leafWidth) {
    if (nodeIndex === root(leafWidth))
        return [];
    const d = directPath(nodeIndex, leafWidth);
    d.unshift(nodeIndex);
    d.pop();
    return d.map((y) => sibling(y, leafWidth));
}
export function isAncestor(childNodeIndex, ancestor, nodeWidth) {
    return directPath(childNodeIndex, leafWidth(nodeWidth)).includes(ancestor);
}
//# sourceMappingURL=treemath.js.map