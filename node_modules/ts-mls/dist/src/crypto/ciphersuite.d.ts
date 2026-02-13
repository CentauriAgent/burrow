import { Signature, SignatureAlgorithm } from "./signature.js";
import { Hash, HashAlgorithm } from "./hash.js";
import { Kdf } from "./kdf.js";
import { Hpke, HpkeAlgorithm } from "./hpke.js";
import { BufferEncoder, Encoder } from "../codec/tlsEncoder.js";
import { Decoder } from "../codec/tlsDecoder.js";
import { Rng } from "./rng.js";
/** @public */
export interface CiphersuiteImpl {
    hash: Hash;
    hpke: Hpke;
    signature: Signature;
    kdf: Kdf;
    rng: Rng;
    name: CiphersuiteName;
}
/** @public */
export declare const ciphersuites: {
    readonly MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519: 1;
    readonly MLS_128_DHKEMP256_AES128GCM_SHA256_P256: 2;
    readonly MLS_128_DHKEMX25519_CHACHA20POLY1305_SHA256_Ed25519: 3;
    readonly MLS_256_DHKEMX448_AES256GCM_SHA512_Ed448: 4;
    readonly MLS_256_DHKEMP521_AES256GCM_SHA512_P521: 5;
    readonly MLS_256_DHKEMX448_CHACHA20POLY1305_SHA512_Ed448: 6;
    readonly MLS_256_DHKEMP384_AES256GCM_SHA384_P384: 7;
    readonly MLS_128_MLKEM512_AES128GCM_SHA256_Ed25519: 77;
    readonly MLS_128_MLKEM512_CHACHA20POLY1305_SHA256_Ed25519: 78;
    readonly MLS_256_MLKEM768_AES256GCM_SHA384_Ed25519: 79;
    readonly MLS_256_MLKEM768_CHACHA20POLY1305_SHA384_Ed25519: 80;
    readonly MLS_256_MLKEM1024_AES256GCM_SHA512_Ed25519: 81;
    readonly MLS_256_MLKEM1024_CHACHA20POLY1305_SHA512_Ed25519: 82;
    readonly MLS_256_XWING_AES256GCM_SHA512_Ed25519: 83;
    readonly MLS_256_XWING_CHACHA20POLY1305_SHA512_Ed25519: 84;
    readonly MLS_256_MLKEM1024_AES256GCM_SHA512_MLDSA87: 85;
    readonly MLS_256_MLKEM1024_CHACHA20POLY1305_SHA512_MLDSA87: 86;
    readonly MLS_256_XWING_AES256GCM_SHA512_MLDSA87: 87;
    readonly MLS_256_XWING_CHACHA20POLY1305_SHA512_MLDSA87: 88;
};
/** @public */
export type CiphersuiteName = keyof typeof ciphersuites;
export type CiphersuiteId = (typeof ciphersuites)[CiphersuiteName];
export declare const ciphersuiteEncoder: BufferEncoder<CiphersuiteName>;
export declare const encodeCiphersuite: Encoder<CiphersuiteName>;
export declare const decodeCiphersuite: Decoder<CiphersuiteName>;
export declare function getCiphersuiteNameFromId(id: CiphersuiteId): CiphersuiteName;
export declare function getCiphersuiteFromId(id: CiphersuiteId): Ciphersuite;
/** @public */
export declare function getCiphersuiteFromName(name: CiphersuiteName): Ciphersuite;
/** @public */
export type Ciphersuite = {
    hash: HashAlgorithm;
    hpke: HpkeAlgorithm;
    signature: SignatureAlgorithm;
    name: CiphersuiteName;
};
