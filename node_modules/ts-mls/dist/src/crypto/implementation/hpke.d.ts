import { CipherSuite } from "@hpke/core";
import { Aead } from "../../crypto/aead.js";
import { HpkeAlgorithm, Hpke } from "../../crypto/hpke.js";
export declare function makeGenericHpke(hpkealg: HpkeAlgorithm, aead: Aead, cs: CipherSuite): Promise<Hpke>;
