import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { Kdf } from "./crypto/kdf.js";
import { GroupContext } from "./groupContext.js";
/** @public */
export interface KeySchedule {
    senderDataSecret: Uint8Array;
    exporterSecret: Uint8Array;
    externalSecret: Uint8Array;
    confirmationKey: Uint8Array;
    membershipKey: Uint8Array;
    resumptionPsk: Uint8Array;
    epochAuthenticator: Uint8Array;
    initSecret: Uint8Array;
}
export declare const keyScheduleEncoder: BufferEncoder<KeySchedule>;
export declare const encodeKeySchedule: Encoder<KeySchedule>;
export declare const decodeKeySchedule: Decoder<KeySchedule>;
export interface EpochSecrets {
    keySchedule: KeySchedule;
    joinerSecret: Uint8Array;
    welcomeSecret: Uint8Array;
    encryptionSecret: Uint8Array;
}
/** @public */
export declare function mlsExporter(exporterSecret: Uint8Array, label: string, context: Uint8Array, length: number, cs: CiphersuiteImpl): Promise<Uint8Array>;
export declare function deriveKeySchedule(joinerSecret: Uint8Array, pskSecret: Uint8Array, groupContext: GroupContext, kdf: Kdf): Promise<[KeySchedule, Uint8Array]>;
export declare function initializeKeySchedule(epochSecret: Uint8Array, kdf: Kdf): Promise<KeySchedule>;
export declare function initializeEpoch(initSecret: Uint8Array, commitSecret: Uint8Array, groupContext: GroupContext, pskSecret: Uint8Array, kdf: Kdf): Promise<EpochSecrets>;
