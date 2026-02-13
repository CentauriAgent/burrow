import { KemId } from "../identifiers.js";
export declare const isDenoV1: () => boolean;
/**
 * Checks whether the runtime is Deno or not (Node.js).
 * @returns boolean - true if the runtime is Deno, false Node.js.
 */
export declare function isDeno(): boolean;
/**
 * Checks whetehr the type of input is CryptoKeyPair or not.
 */
export declare const isCryptoKeyPair: (x: unknown) => x is CryptoKeyPair;
/**
 * Converts integer to octet string. I2OSP implementation.
 */
export declare function i2Osp(n: number, w: number): Uint8Array;
/**
 * Concatenates two Uint8Arrays.
 * @param a Uint8Array
 * @param b Uint8Array
 * @returns Concatenated Uint8Array
 */
export declare function concat(a: Uint8Array, b: Uint8Array): Uint8Array;
/**
 * Decodes Base64Url-encoded data.
 * @param v Base64Url-encoded string
 * @returns Uint8Array
 */
export declare function base64UrlToBytes(v: string): Uint8Array;
/**
 * Encodes Uint8Array to Base64Url.
 * @param v Uint8Array
 * @returns Base64Url-encoded string
 */
export declare function bytesToBase64Url(v: Uint8Array): string;
/**
 * Decodes hex string to Uint8Array.
 * @param v Hex string
 * @returns Uint8Array
 * @throws Error if the input is not a hex string.
 */
export declare function hexToBytes(v: string): Uint8Array;
/**
 * Encodes Uint8Array to hex string.
 * @param v Uint8Array
 * @returns Hex string
 */
export declare function bytesToHex(v: Uint8Array): string;
/**
 * Converts KemId to KeyAlgorithm.
 * @param kem KemId
 * @returns KeyAlgorithm
 */
export declare function kemToKeyGenAlgorithm(kem: KemId): KeyAlgorithm;
export declare function loadSubtleCrypto(): Promise<SubtleCrypto>;
export declare function loadCrypto(): Promise<Crypto>;
/**
 * XOR for Uint8Array.
 */
export declare function xor(a: Uint8Array, b: Uint8Array): Uint8Array;
//# sourceMappingURL=misc.d.ts.map