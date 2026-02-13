/** @public */
export type Encoder<T> = (t: T) => Uint8Array;
export type BufferEncoder<T> = (t: T) => [number, (offset: number, buffer: ArrayBuffer) => void];
export declare function encode<T>(enc: BufferEncoder<T>): Encoder<T>;
export declare function contramapBufferEncoder<T, U>(enc: BufferEncoder<T>, f: (u: U) => Readonly<T>): BufferEncoder<U>;
export declare function contramapBufferEncoders<T extends unknown[], R>(encoders: {
    [K in keyof T]: BufferEncoder<T[K]>;
}, toTuple: (input: R) => T): BufferEncoder<R>;
export declare function composeBufferEncoders<T extends unknown[]>(encoders: {
    [K in keyof T]: BufferEncoder<T[K]>;
}): BufferEncoder<T>;
export declare const encVoid: [number, (offset: number, buffer: ArrayBuffer) => void];
