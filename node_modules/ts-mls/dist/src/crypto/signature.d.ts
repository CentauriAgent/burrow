/** @public */
export interface Signature {
    sign(signKey: Uint8Array, message: Uint8Array): Promise<Uint8Array>;
    verify(publicKey: Uint8Array, message: Uint8Array, signature: Uint8Array): Promise<boolean>;
    keygen(): Promise<{
        publicKey: Uint8Array;
        signKey: Uint8Array;
    }>;
}
/** @public */
export type SignatureAlgorithm = "Ed25519" | "Ed448" | "P256" | "P384" | "P521" | "ML-DSA-87";
export declare function signWithLabel(signKey: Uint8Array, label: string, content: Uint8Array, s: Signature): Promise<Uint8Array>;
export declare function verifyWithLabel(publicKey: Uint8Array, label: string, content: Uint8Array, signature: Uint8Array, s: Signature): Promise<boolean>;
