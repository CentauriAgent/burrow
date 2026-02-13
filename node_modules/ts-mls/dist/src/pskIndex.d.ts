import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { PreSharedKeyID } from "./presharedkey.js";
/** @public */
export interface PskIndex {
    findPsk(preSharedKeyId: PreSharedKeyID): Uint8Array | undefined;
}
/** @public */
export declare const emptyPskIndex: PskIndex;
export declare function accumulatePskSecret(groupedPsk: PreSharedKeyID[], pskSearch: PskIndex, cs: CiphersuiteImpl, zeroes: Uint8Array): Promise<[Uint8Array, PreSharedKeyID[]]>;
