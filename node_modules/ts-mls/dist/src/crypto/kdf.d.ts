/** @public */
export interface Kdf {
    extract(salt: Uint8Array, ikm: Uint8Array): Promise<Uint8Array>;
    expand(prk: Uint8Array, info: Uint8Array, len: number): Promise<Uint8Array>;
    size: number;
}
/** @public */
export type KdfAlgorithm = "HKDF-SHA256" | "HKDF-SHA384" | "HKDF-SHA512";
export declare function expandWithLabel(secret: Uint8Array, label: string, context: Uint8Array, length: number, kdf: Kdf): Promise<Uint8Array>;
export declare function deriveSecret(secret: Uint8Array, label: string, kdf: Kdf): Promise<Uint8Array>;
export declare function deriveTreeSecret(secret: Uint8Array, label: string, generation: number, length: number, kdf: Kdf): Promise<Uint8Array>;
