import { constantTimeEqual } from "./util/constantTimeCompare.js";
/** @public */
export const defaultKeyPackageEqualityConfig = {
    compareKeyPackages(a, b) {
        return constantTimeEqual(a.leafNode.signaturePublicKey, b.leafNode.signaturePublicKey);
    },
    compareKeyPackageToLeafNode(a, b) {
        return constantTimeEqual(a.leafNode.signaturePublicKey, b.signaturePublicKey);
    },
};
//# sourceMappingURL=keyPackageEqualityConfig.js.map