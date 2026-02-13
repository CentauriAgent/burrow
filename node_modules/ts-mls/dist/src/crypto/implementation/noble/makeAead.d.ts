import { AeadInterface } from "@hpke/core";
import { Aead, AeadAlgorithm } from "../../aead.js";
export declare function makeAead(aeadAlg: AeadAlgorithm): Promise<[Aead, AeadInterface]>;
