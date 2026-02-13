/**
 * This file is based on noble-curves (https://github.com/paulmillr/noble-curves).
 *
 * noble-curves - MIT License (c) 2022 Paul Miller (paulmillr.com)
 *
 * The original file is located at:
 * https://github.com/paulmillr/noble-curves/blob/b9d49d2b41d550571a0c5be443ecb62109fa3373/src/abstract/montgomery.ts
 */
import { type CurveLengths } from "./curve.js";
export type CurveType = {
    P: bigint;
    type: "x25519" | "x448";
    adjustScalarBytes: (bytes: Uint8Array) => Uint8Array;
    powPminus2: (x: bigint) => bigint;
    randomBytes?: (bytesLength?: number) => Promise<Uint8Array>;
};
export type MontgomeryECDH = {
    scalarMult: (scalar: Uint8Array, u: Uint8Array) => Uint8Array;
    scalarMultBase: (scalar: Uint8Array) => Uint8Array;
    getSharedSecret: (secretKeyA: Uint8Array, publicKeyB: Uint8Array) => Uint8Array;
    getPublicKey: (secretKey: Uint8Array) => Uint8Array;
    utils: {
        randomSecretKey: (seed?: Uint8Array) => Promise<Uint8Array>;
    };
    GuBytes: Uint8Array;
    lengths: CurveLengths;
    keygen: (seed?: Uint8Array) => {
        secretKey: Uint8Array;
        publicKey: Uint8Array;
    };
};
export declare function montgomery(curveDef: CurveType): MontgomeryECDH;
//# sourceMappingURL=montgomery.d.ts.map