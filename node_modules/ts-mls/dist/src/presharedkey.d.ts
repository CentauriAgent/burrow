import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
export declare const pskTypes: {
    readonly external: 1;
    readonly resumption: 2;
};
export type PSKTypeName = keyof typeof pskTypes;
export type PSKType = (typeof pskTypes)[PSKTypeName];
export declare const pskTypeEncoder: BufferEncoder<PSKTypeName>;
export declare const encodePskType: Encoder<PSKTypeName>;
export declare const decodePskType: Decoder<PSKTypeName>;
/** @public */
export declare const resumptionPSKUsages: {
    readonly application: 1;
    readonly reinit: 2;
    readonly branch: 3;
};
/** @public */
export type ResumptionPSKUsageName = keyof typeof resumptionPSKUsages;
export type ResumptionPSKUsage = (typeof resumptionPSKUsages)[ResumptionPSKUsageName];
export declare const resumptionPSKUsageEncoder: BufferEncoder<ResumptionPSKUsageName>;
export declare const encodeResumptionPSKUsage: Encoder<ResumptionPSKUsageName>;
export declare const decodeResumptionPSKUsage: Decoder<ResumptionPSKUsageName>;
/** @public */
export interface PSKInfoExternal {
    psktype: "external";
    pskId: Uint8Array;
}
/** @public */
export interface PSKInfoResumption {
    psktype: "resumption";
    usage: ResumptionPSKUsageName;
    pskGroupId: Uint8Array;
    pskEpoch: bigint;
}
/** @public */
export type PSKInfo = PSKInfoExternal | PSKInfoResumption;
export declare const pskInfoEncoder: BufferEncoder<PSKInfo>;
export declare const encodePskInfo: Encoder<PSKInfo>;
export declare const decodePskInfo: Decoder<PSKInfo>;
/** @public */
export type PSKNonce = {
    pskNonce: Uint8Array;
};
/** @public */
export type PreSharedKeyID = PSKInfo & PSKNonce;
export declare const pskIdEncoder: BufferEncoder<PreSharedKeyID>;
export declare const encodePskId: Encoder<PreSharedKeyID>;
export declare const decodePskId: Decoder<PreSharedKeyID>;
type PSKLabel = {
    id: PreSharedKeyID;
    index: number;
    count: number;
};
export declare const pskLabelEncoder: BufferEncoder<PSKLabel>;
export declare const encodePskLabel: Encoder<PSKLabel>;
export declare const decodePskLabel: Decoder<PSKLabel>;
export type PreSharedKeyIdExternal = PSKInfoExternal & PSKNonce;
export type PreSharedKeyIdResumption = PSKInfoResumption & PSKNonce;
export declare function computePskSecret(psks: [PreSharedKeyID, Uint8Array][], impl: CiphersuiteImpl): Promise<Uint8Array<ArrayBufferLike>>;
export declare function updatePskSecret(secret: Uint8Array, pskId: PreSharedKeyID, psk: Uint8Array, index: number, count: number, impl: CiphersuiteImpl): Promise<Uint8Array<ArrayBufferLike>>;
export {};
