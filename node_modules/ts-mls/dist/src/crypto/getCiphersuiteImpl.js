import { defaultCryptoProvider } from "./implementation/default/provider.js";
/** @public */
export async function getCiphersuiteImpl(cs, provider = defaultCryptoProvider) {
    return provider.getCiphersuiteImpl(cs);
}
//# sourceMappingURL=getCiphersuiteImpl.js.map