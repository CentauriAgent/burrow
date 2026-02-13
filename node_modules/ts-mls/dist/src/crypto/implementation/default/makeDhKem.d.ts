import { KemInterface } from "@hpke/core";
import { KemAlgorithm } from "../../kem.js";
export declare function makeDhKem(kemAlg: KemAlgorithm): Promise<KemInterface>;
