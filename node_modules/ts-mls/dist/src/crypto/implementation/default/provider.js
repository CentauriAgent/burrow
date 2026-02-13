import { makeHashImpl } from "./makeHashImpl.js";
import { makeHpke } from "./makeHpke.js";
import { makeKdf } from "./makeKdfImpl.js";
import { makeKdfImpl } from "./makeKdfImpl.js";
import { defaultRng } from "./rng.js";
import { makeNobleSignatureImpl } from "./makeNobleSignatureImpl.js";
/** @public */
export const defaultCryptoProvider = {
    async getCiphersuiteImpl(cs) {
        const sc = crypto.subtle;
        return {
            kdf: makeKdfImpl(makeKdf(cs.hpke.kdf)),
            hash: makeHashImpl(sc, cs.hash),
            signature: await makeNobleSignatureImpl(cs.signature),
            hpke: await makeHpke(cs.hpke),
            rng: defaultRng,
            name: cs.name,
        };
    },
};
//# sourceMappingURL=provider.js.map