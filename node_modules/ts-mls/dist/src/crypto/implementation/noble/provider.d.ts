import { Ciphersuite, CiphersuiteImpl } from "../../ciphersuite.js";
/** @public */
export declare const nobleCryptoProvider: {
    getCiphersuiteImpl(cs: Ciphersuite): Promise<CiphersuiteImpl>;
};
