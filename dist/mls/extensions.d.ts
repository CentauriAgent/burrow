/**
 * Marmot Group Data Extension (0xF2EE) — TLS serialization.
 * Per MIP-01: TLS presentation language serialization with proper length prefixes.
 */
import type { MarmotGroupData } from '../types/index.js';
/**
 * Encode MarmotGroupData to TLS binary format per MIP-01.
 */
export declare function encodeMarmotGroupData(mgd: MarmotGroupData): Uint8Array;
/**
 * Decode MarmotGroupData from TLS binary format.
 */
export declare function decodeMarmotGroupData(data: Uint8Array): MarmotGroupData;
/**
 * Create a Marmot Group Data extension entry for ts-mls.
 */
export declare function createMarmotExtension(mgd: MarmotGroupData): {
    extensionType: number;
    extensionData: Uint8Array;
};
//# sourceMappingURL=extensions.d.ts.map