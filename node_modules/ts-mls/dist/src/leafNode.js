import { capabilitiesEncoder, decodeCapabilities } from "./capabilities.js";
import { decodeUint32, uint32Encoder } from "./codec/number.js";
import { mapDecoders, flatMapDecoder, mapDecoderOption, mapDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { varLenDataEncoder, decodeVarLenData, varLenTypeEncoder, decodeVarLenType } from "./codec/variableLength.js";
import { credentialEncoder, decodeCredential } from "./credential.js";
import { signWithLabel, verifyWithLabel } from "./crypto/signature.js";
import { extensionEncoder, decodeExtension } from "./extension.js";
import { leafNodeSourceEncoder, decodeLeafNodeSource } from "./leafNodeSource.js";
import { lifetimeEncoder, decodeLifetime } from "./lifetime.js";
export const leafNodeDataEncoder = contramapBufferEncoders([varLenDataEncoder, varLenDataEncoder, credentialEncoder, capabilitiesEncoder], (data) => [data.hpkePublicKey, data.signaturePublicKey, data.credential, data.capabilities]);
export const encodeLeafNodeData = encode(leafNodeDataEncoder);
export const decodeLeafNodeData = mapDecoders([decodeVarLenData, decodeVarLenData, decodeCredential, decodeCapabilities], (hpkePublicKey, signaturePublicKey, credential, capabilities) => ({
    hpkePublicKey,
    signaturePublicKey,
    credential,
    capabilities,
}));
export const leafNodeInfoKeyPackageEncoder = contramapBufferEncoders([leafNodeSourceEncoder, lifetimeEncoder, varLenTypeEncoder(extensionEncoder)], (info) => ["key_package", info.lifetime, info.extensions]);
export const encodeLeafNodeInfoKeyPackage = encode(leafNodeInfoKeyPackageEncoder);
export const leafNodeInfoUpdateOmittedEncoder = contramapBufferEncoders([leafNodeSourceEncoder, varLenTypeEncoder(extensionEncoder)], (i) => [i.leafNodeSource, i.extensions]);
export const encodeLeafNodeInfoUpdateOmitted = encode(leafNodeInfoUpdateOmittedEncoder);
export const leafNodeInfoCommitOmittedEncoder = contramapBufferEncoders([leafNodeSourceEncoder, varLenDataEncoder, varLenTypeEncoder(extensionEncoder)], (info) => [info.leafNodeSource, info.parentHash, info.extensions]);
export const encodeLeafNodeInfoCommitOmitted = encode(leafNodeInfoCommitOmittedEncoder);
export const leafNodeInfoOmittedEncoder = (info) => {
    switch (info.leafNodeSource) {
        case "key_package":
            return leafNodeInfoKeyPackageEncoder(info);
        case "update":
            return leafNodeInfoUpdateOmittedEncoder(info);
        case "commit":
            return leafNodeInfoCommitOmittedEncoder(info);
    }
};
export const encodeLeafNodeInfoOmitted = encode(leafNodeInfoOmittedEncoder);
export const decodeLeafNodeInfoKeyPackage = mapDecoders([decodeLifetime, decodeVarLenType(decodeExtension)], (lifetime, extensions) => ({
    leafNodeSource: "key_package",
    lifetime,
    extensions,
}));
export const decodeLeafNodeInfoUpdateOmitted = mapDecoder(decodeVarLenType(decodeExtension), (extensions) => ({
    leafNodeSource: "update",
    extensions,
}));
export const decodeLeafNodeInfoCommitOmitted = mapDecoders([decodeVarLenData, decodeVarLenType(decodeExtension)], (parentHash, extensions) => ({
    leafNodeSource: "commit",
    parentHash,
    extensions,
}));
export const decodeLeafNodeInfoOmitted = flatMapDecoder(decodeLeafNodeSource, (leafNodeSource) => {
    switch (leafNodeSource) {
        case "key_package":
            return decodeLeafNodeInfoKeyPackage;
        case "update":
            return decodeLeafNodeInfoUpdateOmitted;
        case "commit":
            return decodeLeafNodeInfoCommitOmitted;
    }
});
export const leafNodeInfoUpdateEncoder = contramapBufferEncoders([leafNodeInfoUpdateOmittedEncoder, varLenDataEncoder, uint32Encoder], (i) => [i, i.groupId, i.leafIndex]);
export const encodeLeafNodeInfoUpdate = encode(leafNodeInfoUpdateEncoder);
export const leafNodeInfoCommitEncoder = contramapBufferEncoders([leafNodeInfoCommitOmittedEncoder, varLenDataEncoder, uint32Encoder], (info) => [info, info.groupId, info.leafIndex]);
export const encodeLeafNodeInfoCommit = encode(leafNodeInfoCommitEncoder);
export const leafNodeInfoEncoder = (info) => {
    switch (info.leafNodeSource) {
        case "key_package":
            return leafNodeInfoKeyPackageEncoder(info);
        case "update":
            return leafNodeInfoUpdateEncoder(info);
        case "commit":
            return leafNodeInfoCommitEncoder(info);
    }
};
export const encodeLeafNodeInfo = encode(leafNodeInfoEncoder);
export const decodeLeafNodeInfoUpdate = mapDecoders([decodeLeafNodeInfoUpdateOmitted, decodeVarLenData, decodeUint32], (ln, groupId, leafIndex) => ({
    ...ln,
    groupId,
    leafIndex,
}));
export const decodeLeafNodeInfoCommit = mapDecoders([decodeLeafNodeInfoCommitOmitted, decodeVarLenData, decodeUint32], (ln, groupId, leafIndex) => ({
    ...ln,
    groupId,
    leafIndex,
}));
export const decodeLeafNodeInfo = flatMapDecoder(decodeLeafNodeSource, (leafNodeSource) => {
    switch (leafNodeSource) {
        case "key_package":
            return decodeLeafNodeInfoKeyPackage;
        case "update":
            return decodeLeafNodeInfoUpdate;
        case "commit":
            return decodeLeafNodeInfoCommit;
    }
});
export const leafNodeTBSEncoder = contramapBufferEncoders([leafNodeDataEncoder, leafNodeInfoEncoder], (tbs) => [tbs, tbs]);
export const encodeLeafNodeTBS = encode(leafNodeTBSEncoder);
export const leafNodeEncoder = contramapBufferEncoders([leafNodeDataEncoder, leafNodeInfoOmittedEncoder, varLenDataEncoder], (leafNode) => [leafNode, leafNode, leafNode.signature]);
export const encodeLeafNode = encode(leafNodeEncoder);
export const decodeLeafNode = mapDecoders([decodeLeafNodeData, decodeLeafNodeInfoOmitted, decodeVarLenData], (data, info, signature) => ({
    ...data,
    ...info,
    signature,
}));
export const decodeLeafNodeKeyPackage = mapDecoderOption(decodeLeafNode, (ln) => ln.leafNodeSource === "key_package" ? ln : undefined);
export const decodeLeafNodeCommit = mapDecoderOption(decodeLeafNode, (ln) => ln.leafNodeSource === "commit" ? ln : undefined);
export const decodeLeafNodeUpdate = mapDecoderOption(decodeLeafNode, (ln) => ln.leafNodeSource === "update" ? ln : undefined);
function toTbs(leafNode, groupId, leafIndex) {
    switch (leafNode.leafNodeSource) {
        case "key_package":
            return { ...leafNode, leafNodeSource: leafNode.leafNodeSource };
        case "update":
            return { ...leafNode, leafNodeSource: leafNode.leafNodeSource, groupId, leafIndex };
        case "commit":
            return { ...leafNode, leafNodeSource: leafNode.leafNodeSource, groupId, leafIndex };
    }
}
export async function signLeafNodeCommit(tbs, signaturePrivateKey, sig) {
    return {
        ...tbs,
        signature: await signWithLabel(signaturePrivateKey, "LeafNodeTBS", encode(leafNodeTBSEncoder)(tbs), sig),
    };
}
export async function signLeafNodeKeyPackage(tbs, signaturePrivateKey, sig) {
    return {
        ...tbs,
        signature: await signWithLabel(signaturePrivateKey, "LeafNodeTBS", encode(leafNodeTBSEncoder)(tbs), sig),
    };
}
export function verifyLeafNodeSignature(leaf, groupId, leafIndex, sig) {
    return verifyWithLabel(leaf.signaturePublicKey, "LeafNodeTBS", encode(leafNodeTBSEncoder)(toTbs(leaf, groupId, leafIndex)), leaf.signature, sig);
}
export function verifyLeafNodeSignatureKeyPackage(leaf, sig) {
    return verifyWithLabel(leaf.signaturePublicKey, "LeafNodeTBS", encode(leafNodeTBSEncoder)(leaf), leaf.signature, sig);
}
//# sourceMappingURL=leafNode.js.map