/**
 * This file is based on noble-curves (https://github.com/paulmillr/noble-curves).
 *
 * noble-curves - MIT License (c) 2022 Paul Miller (paulmillr.com)
 *
 * The original file is located at:
 * https://github.com/paulmillr/noble-curves/blob/b9d49d2b41d550571a0c5be443ecb62109fa3373/src/abstract/modular.ts
 */
export declare function mod(a: bigint, b: bigint): bigint;
/** Does `x^(2^power)` mod p. `pow2(30, 4)` == `30^(2^4)` */
export declare function pow2(x: bigint, power: bigint, modulo: bigint): bigint;
//# sourceMappingURL=modular.d.ts.map