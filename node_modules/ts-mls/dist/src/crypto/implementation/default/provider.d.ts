import { Ciphersuite, CiphersuiteImpl } from "../../ciphersuite.js";
/** @public */
export declare const defaultCryptoProvider: {
    getCiphersuiteImpl(cs: Ciphersuite): Promise<CiphersuiteImpl>;
};
