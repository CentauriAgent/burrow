export declare function enumNumberToKey<S extends string>(t: Record<S, number>): (n: number) => S | undefined;
export declare function reverseMap<T extends Record<string, number>>(obj: T): Record<number, string>;
export declare function openEnumNumberToKey<S extends string>(rec: Record<S, number>): (n: number) => S | undefined;
export declare function openEnumNumberEncoder<S extends string>(rec: Record<S, number>): (s: S) => number;
