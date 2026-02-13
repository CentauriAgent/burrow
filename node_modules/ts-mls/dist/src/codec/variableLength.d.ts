import { Decoder } from "./tlsDecoder.js";
import { BufferEncoder } from "./tlsEncoder.js";
export declare const varLenDataEncoder: BufferEncoder<Uint8Array>;
export declare function lengthEncoder(len: number): [number, (offset: number, buffer: ArrayBuffer) => void];
export declare function determineLength(data: Uint8Array, offset?: number): {
    length: number;
    lengthFieldSize: number;
};
export declare const decodeVarLenData: Decoder<Uint8Array>;
export declare function varLenTypeEncoder<T>(enc: BufferEncoder<T>): BufferEncoder<T[]>;
export declare function decodeVarLenType<T>(dec: Decoder<T>): Decoder<T[]>;
export declare function base64RecordEncoder<V>(valueEncoder: BufferEncoder<V>): BufferEncoder<Record<string, V>>;
export declare function decodeBase64Record<V>(decodeValue: Decoder<V>): Decoder<Record<string, V>>;
export declare function numberRecordEncoder<V>(numberEncoder: BufferEncoder<number>, valueEncoder: BufferEncoder<V>): BufferEncoder<Record<number, V>>;
export declare function decodeNumberRecord<V>(decodeNumber: Decoder<number>, decodeValue: Decoder<V>): Decoder<Record<number, V>>;
export declare function bigintMapEncoder<V>(valueEncoder: BufferEncoder<V>): BufferEncoder<Map<bigint, V>>;
export declare function decodeBigintMap<V>(decodeValue: Decoder<V>): Decoder<Map<bigint, V>>;
