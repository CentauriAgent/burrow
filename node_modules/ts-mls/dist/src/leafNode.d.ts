import { Capabilities } from "./capabilities.js";
import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { Credential } from "./credential.js";
import { Signature } from "./crypto/signature.js";
import { Extension } from "./extension.js";
import { Lifetime } from "./lifetime.js";
/** @public */
export interface LeafNodeData {
    hpkePublicKey: Uint8Array;
    signaturePublicKey: Uint8Array;
    credential: Credential;
    capabilities: Capabilities;
}
export declare const leafNodeDataEncoder: BufferEncoder<LeafNodeData>;
export declare const encodeLeafNodeData: Encoder<LeafNodeData>;
export declare const decodeLeafNodeData: Decoder<LeafNodeData>;
/** @public */
export type LeafNodeInfoOmitted = LeafNodeInfoKeyPackage | LeafNodeInfoUpdateOmitted | LeafNodeInfoCommitOmitted;
/** @public */
export interface LeafNodeInfoUpdateOmitted {
    leafNodeSource: "update";
    extensions: Extension[];
}
/** @public */
export interface LeafNodeInfoCommitOmitted {
    leafNodeSource: "commit";
    parentHash: Uint8Array;
    extensions: Extension[];
}
/** @public */
export interface LeafNodeInfoKeyPackage {
    leafNodeSource: "key_package";
    lifetime: Lifetime;
    extensions: Extension[];
}
export declare const leafNodeInfoKeyPackageEncoder: BufferEncoder<LeafNodeInfoKeyPackage>;
export declare const encodeLeafNodeInfoKeyPackage: Encoder<LeafNodeInfoKeyPackage>;
export declare const leafNodeInfoUpdateOmittedEncoder: BufferEncoder<LeafNodeInfoUpdateOmitted>;
export declare const encodeLeafNodeInfoUpdateOmitted: Encoder<LeafNodeInfoUpdate>;
export declare const leafNodeInfoCommitOmittedEncoder: BufferEncoder<LeafNodeInfoCommitOmitted>;
export declare const encodeLeafNodeInfoCommitOmitted: Encoder<LeafNodeInfoCommitOmitted>;
export declare const leafNodeInfoOmittedEncoder: BufferEncoder<LeafNodeInfoOmitted>;
export declare const encodeLeafNodeInfoOmitted: Encoder<LeafNodeInfoOmitted>;
export declare const decodeLeafNodeInfoKeyPackage: Decoder<LeafNodeInfoKeyPackage>;
export declare const decodeLeafNodeInfoUpdateOmitted: Decoder<LeafNodeInfoUpdateOmitted>;
export declare const decodeLeafNodeInfoCommitOmitted: Decoder<LeafNodeInfoCommitOmitted>;
export declare const decodeLeafNodeInfoOmitted: Decoder<LeafNodeInfoOmitted>;
export type LeafNodeInfo = LeafNodeInfoKeyPackage | LeafNodeInfoUpdate | LeafNodeInfoCommit;
export type LeafNodeInfoUpdate = LeafNodeInfoUpdateOmitted & {
    groupId: Uint8Array;
    leafIndex: number;
};
export type LeafNodeInfoCommit = LeafNodeInfoCommitOmitted & {
    groupId: Uint8Array;
    leafIndex: number;
};
export declare const leafNodeInfoUpdateEncoder: BufferEncoder<LeafNodeInfoUpdate>;
export declare const encodeLeafNodeInfoUpdate: Encoder<LeafNodeInfoUpdate>;
export declare const leafNodeInfoCommitEncoder: BufferEncoder<LeafNodeInfoCommit>;
export declare const encodeLeafNodeInfoCommit: Encoder<LeafNodeInfoCommit>;
export declare const leafNodeInfoEncoder: BufferEncoder<LeafNodeInfo>;
export declare const encodeLeafNodeInfo: Encoder<LeafNodeInfo>;
export declare const decodeLeafNodeInfoUpdate: Decoder<LeafNodeInfoUpdate>;
export declare const decodeLeafNodeInfoCommit: Decoder<LeafNodeInfoCommit>;
export declare const decodeLeafNodeInfo: Decoder<LeafNodeInfo>;
export type LeafNodeTBS = LeafNodeData & LeafNodeInfo;
export type LeafNodeTBSCommit = LeafNodeData & LeafNodeInfoCommit;
export type LeafNodeTBSKeyPackage = LeafNodeData & LeafNodeInfoKeyPackage;
export declare const leafNodeTBSEncoder: BufferEncoder<LeafNodeTBS>;
export declare const encodeLeafNodeTBS: Encoder<LeafNodeTBS>;
/** @public */
export type LeafNode = LeafNodeData & LeafNodeInfoOmitted & {
    signature: Uint8Array;
};
export declare const leafNodeEncoder: BufferEncoder<LeafNode>;
export declare const encodeLeafNode: Encoder<LeafNode>;
export declare const decodeLeafNode: Decoder<LeafNode>;
/** @public */
export type LeafNodeKeyPackage = LeafNode & {
    leafNodeSource: "key_package";
};
export declare const decodeLeafNodeKeyPackage: Decoder<LeafNodeKeyPackage>;
/** @public */
export type LeafNodeCommit = LeafNode & {
    leafNodeSource: "commit";
};
export declare const decodeLeafNodeCommit: Decoder<LeafNodeCommit>;
/** @public */
export type LeafNodeUpdate = LeafNode & {
    leafNodeSource: "update";
};
export declare const decodeLeafNodeUpdate: Decoder<LeafNodeUpdate>;
export declare function signLeafNodeCommit(tbs: LeafNodeTBSCommit, signaturePrivateKey: Uint8Array, sig: Signature): Promise<LeafNodeCommit>;
export declare function signLeafNodeKeyPackage(tbs: LeafNodeTBSKeyPackage, signaturePrivateKey: Uint8Array, sig: Signature): Promise<LeafNodeKeyPackage>;
export declare function verifyLeafNodeSignature(leaf: LeafNode, groupId: Uint8Array, leafIndex: number, sig: Signature): Promise<boolean>;
export declare function verifyLeafNodeSignatureKeyPackage(leaf: LeafNodeKeyPackage, sig: Signature): Promise<boolean>;
