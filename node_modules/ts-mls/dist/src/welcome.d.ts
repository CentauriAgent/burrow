import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl, CiphersuiteName } from "./crypto/ciphersuite.js";
import { PublicKey, Hpke, PrivateKey } from "./crypto/hpke.js";
import { GroupInfo } from "./groupInfo.js";
import { GroupSecrets } from "./groupSecrets.js";
import { HPKECiphertext } from "./hpkeCiphertext.js";
/** @public */
export interface EncryptedGroupSecrets {
    newMember: Uint8Array;
    encryptedGroupSecrets: HPKECiphertext;
}
export declare const encryptedGroupSecretsEncoder: BufferEncoder<EncryptedGroupSecrets>;
export declare const encodeEncryptedGroupSecrets: Encoder<EncryptedGroupSecrets>;
export declare const decodeEncryptedGroupSecrets: Decoder<EncryptedGroupSecrets>;
/** @public */
export interface Welcome {
    cipherSuite: CiphersuiteName;
    secrets: EncryptedGroupSecrets[];
    encryptedGroupInfo: Uint8Array;
}
export declare const welcomeEncoder: BufferEncoder<Welcome>;
export declare const encodeWelcome: Encoder<Welcome>;
export declare const decodeWelcome: Decoder<Welcome>;
export declare function welcomeNonce(welcomeSecret: Uint8Array, cs: CiphersuiteImpl): Promise<Uint8Array<ArrayBufferLike>>;
export declare function welcomeKey(welcomeSecret: Uint8Array, cs: CiphersuiteImpl): Promise<Uint8Array<ArrayBufferLike>>;
export declare function encryptGroupInfo(groupInfo: GroupInfo, welcomeSecret: Uint8Array, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function decryptGroupInfo(w: Welcome, joinerSecret: Uint8Array, pskSecret: Uint8Array, cs: CiphersuiteImpl): Promise<GroupInfo | undefined>;
export declare function encryptGroupSecrets(initKey: PublicKey, encryptedGroupInfo: Uint8Array, groupSecrets: GroupSecrets, hpke: Hpke): Promise<{
    ct: Uint8Array;
    enc: Uint8Array;
}>;
export declare function decryptGroupSecrets(initPrivateKey: PrivateKey, keyPackageRef: Uint8Array, welcome: Welcome, hpke: Hpke): Promise<GroupSecrets | undefined>;
