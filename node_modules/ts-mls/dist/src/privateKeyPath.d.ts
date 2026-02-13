import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { PathSecrets } from "./pathSecrets.js";
/** @public */
export interface PrivateKeyPath {
    leafIndex: number;
    privateKeys: Record<number, Uint8Array>;
}
export declare const privateKeyPathEncoder: BufferEncoder<PrivateKeyPath>;
export declare const decodePrivateKeyPath: Decoder<PrivateKeyPath>;
/**
 * Merges PrivateKeyPaths, BEWARE, if there is a conflict, this function will prioritize the second `b` parameter
 */
export declare function mergePrivateKeyPaths(a: PrivateKeyPath, b: PrivateKeyPath): PrivateKeyPath;
export declare function updateLeafKey(path: PrivateKeyPath, newKey: Uint8Array): PrivateKeyPath;
export declare function toPrivateKeyPath(pathSecrets: PathSecrets, leafIndex: number, cs: CiphersuiteImpl): Promise<PrivateKeyPath>;
