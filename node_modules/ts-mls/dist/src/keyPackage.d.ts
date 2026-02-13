import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl, CiphersuiteName } from "./crypto/ciphersuite.js";
import { Hash } from "./crypto/hash.js";
import { Signature } from "./crypto/signature.js";
import { Extension } from "./extension.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { LeafNodeKeyPackage } from "./leafNode.js";
import { Capabilities } from "./capabilities.js";
import { Lifetime } from "./lifetime.js";
import { Credential } from "./credential.js";
/** @public */
export type KeyPackageTBS = {
    version: ProtocolVersionName;
    cipherSuite: CiphersuiteName;
    initKey: Uint8Array;
    leafNode: LeafNodeKeyPackage;
    extensions: Extension[];
};
export declare const keyPackageTBSEncoder: BufferEncoder<KeyPackageTBS>;
export declare const encodeKeyPackageTBS: Encoder<KeyPackageTBS>;
export declare const decodeKeyPackageTBS: Decoder<KeyPackageTBS>;
/** @public */
export type KeyPackage = KeyPackageTBS & {
    signature: Uint8Array;
};
export declare const keyPackageEncoder: BufferEncoder<KeyPackage>;
export declare const encodeKeyPackage: Encoder<KeyPackage>;
export declare const decodeKeyPackage: Decoder<KeyPackage>;
export declare function signKeyPackage(tbs: KeyPackageTBS, signKey: Uint8Array, s: Signature): Promise<KeyPackage>;
export declare function verifyKeyPackage(kp: KeyPackage, s: Signature): Promise<boolean>;
export declare function makeKeyPackageRef(value: KeyPackage, h: Hash): Promise<Uint8Array>;
/** @public */
export interface PrivateKeyPackage {
    initPrivateKey: Uint8Array;
    hpkePrivateKey: Uint8Array;
    signaturePrivateKey: Uint8Array;
}
/** @public */
export declare function generateKeyPackageWithKey(credential: Credential, capabilities: Capabilities, lifetime: Lifetime, extensions: Extension[], signatureKeyPair: {
    signKey: Uint8Array;
    publicKey: Uint8Array;
}, cs: CiphersuiteImpl, leafNodeExtensions?: Extension[]): Promise<{
    publicPackage: KeyPackage;
    privatePackage: PrivateKeyPackage;
}>;
/** @public */
export declare function generateKeyPackage(credential: Credential, capabilities: Capabilities, lifetime: Lifetime, extensions: Extension[], cs: CiphersuiteImpl, leafNodeExtensions?: Extension[]): Promise<{
    publicPackage: KeyPackage;
    privatePackage: PrivateKeyPackage;
}>;
