import { Ciphersuite, CiphersuiteImpl } from "./ciphersuite.js";
import { CryptoProvider } from "./provider.js";
/** @public */
export declare function getCiphersuiteImpl(cs: Ciphersuite, provider?: CryptoProvider): Promise<CiphersuiteImpl>;
