/** @public */
export type Decoder<T> = (b: Uint8Array, offset: number) => [T, number] | undefined;
export declare function mapDecoder<T, U>(dec: Decoder<T>, f: (t: T) => U): Decoder<U>;
export declare function mapDecodersOption<T extends unknown[], R>(decoders: {
    [K in keyof T]: Decoder<T[K]>;
}, f: (...args: T) => R | undefined): Decoder<R>;
export declare function mapDecoders<T extends unknown[], R>(decoders: {
    [K in keyof T]: Decoder<T[K]>;
}, f: (...args: T) => R): Decoder<R>;
export declare function mapDecoderOption<T, U>(dec: Decoder<T>, f: (t: T) => U | undefined): Decoder<U>;
export declare function flatMapDecoder<T, U>(dec: Decoder<T>, f: (t: T) => Decoder<U>): Decoder<U>;
export declare function orDecoder<T, U>(decT: Decoder<T>, decU: Decoder<U>): Decoder<T | U>;
export declare function flatMapDecoderAndMap<T, U, V>(dec: Decoder<T>, f: (t: T) => Decoder<U>, g: (t: T, u: U) => V): Decoder<V>;
export declare function succeedDecoder<T>(t: T): Decoder<T>;
export declare function failDecoder<T>(): Decoder<T>;
