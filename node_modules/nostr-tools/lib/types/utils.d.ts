import type { NostrEvent } from './core.ts';
export declare const utf8Decoder: TextDecoder;
export declare const utf8Encoder: TextEncoder;
export { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
export declare function normalizeURL(url: string): string;
export declare function insertEventIntoDescendingList(sortedArray: NostrEvent[], event: NostrEvent): NostrEvent[];
export declare function insertEventIntoAscendingList(sortedArray: NostrEvent[], event: NostrEvent): NostrEvent[];
export declare function binarySearch<T>(arr: T[], compare: (b: T) => number): [number, boolean];
export declare function mergeReverseSortedLists(list1: NostrEvent[], list2: NostrEvent[]): NostrEvent[];
