import { AeadInterface } from "@hpke/core";
import { AeadAlgorithm, Aead } from "../../aead.js";
export declare function makeAead(aeadAlg: AeadAlgorithm): Promise<[Aead, AeadInterface]>;
