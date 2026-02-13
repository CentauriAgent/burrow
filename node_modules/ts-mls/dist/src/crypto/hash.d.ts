/** @public */
export type HashAlgorithm = "SHA-512" | "SHA-384" | "SHA-256";
/** @public */
export interface Hash {
    digest(data: Uint8Array): Promise<Uint8Array>;
    mac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array>;
    verifyMac(key: Uint8Array, mac: Uint8Array, data: Uint8Array): Promise<boolean>;
}
export declare function refhash(label: string, value: Uint8Array, h: Hash): Promise<Uint8Array<ArrayBufferLike>>;
