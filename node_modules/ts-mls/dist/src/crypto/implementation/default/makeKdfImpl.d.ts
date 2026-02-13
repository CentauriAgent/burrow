import { KdfInterface } from "@hpke/core";
import { Kdf, KdfAlgorithm } from "../../kdf.js";
export declare function makeKdfImpl(k: KdfInterface): Kdf;
export declare function makeKdf(kdfAlg: KdfAlgorithm): KdfInterface;
