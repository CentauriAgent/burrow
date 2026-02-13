import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { ciphersuiteEncoder, decodeCiphersuite } from "./crypto/ciphersuite.js";
import { refhash } from "./crypto/hash.js";
import { signWithLabel, verifyWithLabel } from "./crypto/signature.js";
import { decodeExtension, extensionEncoder } from "./extension.js";
import { decodeProtocolVersion, protocolVersionEncoder } from "./protocolVersion.js";
import { decodeLeafNodeKeyPackage, leafNodeEncoder, signLeafNodeKeyPackage, } from "./leafNode.js";
export const keyPackageTBSEncoder = contramapBufferEncoders([protocolVersionEncoder, ciphersuiteEncoder, varLenDataEncoder, leafNodeEncoder, varLenTypeEncoder(extensionEncoder)], (keyPackageTBS) => [
    keyPackageTBS.version,
    keyPackageTBS.cipherSuite,
    keyPackageTBS.initKey,
    keyPackageTBS.leafNode,
    keyPackageTBS.extensions,
]);
export const encodeKeyPackageTBS = encode(keyPackageTBSEncoder);
export const decodeKeyPackageTBS = mapDecoders([
    decodeProtocolVersion,
    decodeCiphersuite,
    decodeVarLenData,
    decodeLeafNodeKeyPackage,
    decodeVarLenType(decodeExtension),
], (version, cipherSuite, initKey, leafNode, extensions) => ({
    version,
    cipherSuite,
    initKey,
    leafNode,
    extensions,
}));
export const keyPackageEncoder = contramapBufferEncoders([keyPackageTBSEncoder, varLenDataEncoder], (keyPackage) => [keyPackage, keyPackage.signature]);
export const encodeKeyPackage = encode(keyPackageEncoder);
export const decodeKeyPackage = mapDecoders([decodeKeyPackageTBS, decodeVarLenData], (keyPackageTBS, signature) => ({
    ...keyPackageTBS,
    signature,
}));
export async function signKeyPackage(tbs, signKey, s) {
    return { ...tbs, signature: await signWithLabel(signKey, "KeyPackageTBS", encode(keyPackageTBSEncoder)(tbs), s) };
}
export async function verifyKeyPackage(kp, s) {
    return verifyWithLabel(kp.leafNode.signaturePublicKey, "KeyPackageTBS", encode(keyPackageTBSEncoder)(kp), kp.signature, s);
}
export function makeKeyPackageRef(value, h) {
    return refhash("MLS 1.0 KeyPackage Reference", encode(keyPackageEncoder)(value), h);
}
/** @public */
export async function generateKeyPackageWithKey(credential, capabilities, lifetime, extensions, signatureKeyPair, cs, leafNodeExtensions) {
    const initKeys = await cs.hpke.generateKeyPair();
    const hpkeKeys = await cs.hpke.generateKeyPair();
    const privatePackage = {
        initPrivateKey: await cs.hpke.exportPrivateKey(initKeys.privateKey),
        hpkePrivateKey: await cs.hpke.exportPrivateKey(hpkeKeys.privateKey),
        signaturePrivateKey: signatureKeyPair.signKey,
    };
    const leafNodeTbs = {
        leafNodeSource: "key_package",
        hpkePublicKey: await cs.hpke.exportPublicKey(hpkeKeys.publicKey),
        signaturePublicKey: signatureKeyPair.publicKey,
        extensions: leafNodeExtensions ?? [],
        credential,
        capabilities,
        lifetime,
    };
    const tbs = {
        version: "mls10",
        cipherSuite: cs.name,
        initKey: await cs.hpke.exportPublicKey(initKeys.publicKey),
        leafNode: await signLeafNodeKeyPackage(leafNodeTbs, signatureKeyPair.signKey, cs.signature),
        extensions,
    };
    return { publicPackage: await signKeyPackage(tbs, signatureKeyPair.signKey, cs.signature), privatePackage };
}
/** @public */
export async function generateKeyPackage(credential, capabilities, lifetime, extensions, cs, leafNodeExtensions) {
    const sigKeys = await cs.signature.keygen();
    return generateKeyPackageWithKey(credential, capabilities, lifetime, extensions, sigKeys, cs, leafNodeExtensions);
}
//# sourceMappingURL=keyPackage.js.map