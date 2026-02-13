import { CipherSuite } from "@hpke/core";
import { makeGenericHpke } from "../hpke.js";
import { makeAead } from "./makeAead.js";
import { makeKdf } from "./makeKdfImpl.js";
import { makeDhKem } from "./makeDhKem.js";
export async function makeHpke(hpkealg) {
    const [aead, aeadInterface] = await makeAead(hpkealg.aead);
    const cs = new CipherSuite({
        kem: await makeDhKem(hpkealg.kem),
        kdf: makeKdf(hpkealg.kdf),
        aead: aeadInterface,
    });
    return makeGenericHpke(hpkealg, aead, cs);
}
//# sourceMappingURL=makeHpke.js.map