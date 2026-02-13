import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder } from "./codec/tlsEncoder.js";
import { ContentTypeName } from "./contentType.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Kdf } from "./crypto/kdf.js";
import { KeyRetentionConfig } from "./keyRetentionConfig.js";
import { ReuseGuard, SenderData } from "./sender.js";
/** @public */
export interface GenerationSecret {
    secret: Uint8Array;
    generation: number;
    unusedGenerations: Record<number, Uint8Array>;
}
export declare const generationSecretEncoder: BufferEncoder<GenerationSecret>;
export declare const decodeGenerationSecret: Decoder<GenerationSecret>;
/** @public */
export interface SecretTreeNode {
    handshake: GenerationSecret;
    application: GenerationSecret;
}
export declare const secretTreeNodeEncoder: BufferEncoder<SecretTreeNode>;
export declare const decodeSecretTreeNode: Decoder<SecretTreeNode>;
/** @public */
export type SecretTree = SecretTreeNode[];
export declare const secretTreeEncoder: BufferEncoder<SecretTree>;
export declare const decodeSecretTree: Decoder<SecretTree>;
export declare function allSecretTreeValues(tree: SecretTree): Uint8Array[];
export interface ConsumeRatchetResult {
    nonce: Uint8Array;
    reuseGuard: ReuseGuard;
    key: Uint8Array;
    generation: number;
    newTree: SecretTree;
    consumed: Uint8Array[];
}
export declare function createSecretTree(leafWidth: number, encryptionSecret: Uint8Array, kdf: Kdf): Promise<SecretTree>;
export declare function deriveNonce(secret: Uint8Array, generation: number, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function deriveKey(secret: Uint8Array, generation: number, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function ratchetUntil(current: GenerationSecret, desiredGen: number, config: KeyRetentionConfig, kdf: Kdf): Promise<[GenerationSecret, Uint8Array[]]>;
export declare function derivePrivateMessageNonce(secret: Uint8Array, generation: number, reuseGuard: Uint8Array, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function ratchetToGeneration(tree: SecretTree, senderData: SenderData, contentType: ContentTypeName, config: KeyRetentionConfig, cs: CiphersuiteImpl): Promise<ConsumeRatchetResult>;
export declare function consumeRatchet(tree: SecretTree, index: number, contentType: ContentTypeName, cs: CiphersuiteImpl): Promise<ConsumeRatchetResult>;
