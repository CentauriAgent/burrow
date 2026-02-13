import { KeyPackage } from "./keyPackage.js";
import { LeafNode } from "./leafNode.js";
/** @public */
export interface KeyPackageEqualityConfig {
    compareKeyPackages(a: KeyPackage, b: KeyPackage): boolean;
    compareKeyPackageToLeafNode(a: KeyPackage, b: LeafNode): boolean;
}
/** @public */
export declare const defaultKeyPackageEqualityConfig: KeyPackageEqualityConfig;
