import { stringEncoder, decodeString } from "./codec/string.js";
import { flatMapDecoder, succeedDecoder, mapDecoder, failDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders } from "./codec/tlsEncoder.js";
import { reinitEncoder, decodeReinit } from "./proposal.js";
const activeEncoder = contramapBufferEncoder(stringEncoder, () => "active");
const suspendedPendingReinitEncoder = contramapBufferEncoders([stringEncoder, reinitEncoder], (s) => ["suspendedPendingReinit", s.reinit]);
const removedFromGroupEncoder = contramapBufferEncoder(stringEncoder, () => "removedFromGroup");
export const groupActiveStateEncoder = (state) => {
    switch (state.kind) {
        case "active":
            return activeEncoder(state);
        case "suspendedPendingReinit":
            return suspendedPendingReinitEncoder(state);
        case "removedFromGroup":
            return removedFromGroupEncoder(state);
    }
};
export const decodeGroupActiveState = flatMapDecoder(decodeString, (kind) => {
    switch (kind) {
        case "active":
            return succeedDecoder({ kind: "active" });
        case "suspendedPendingReinit":
            return mapDecoder(decodeReinit, (reinit) => ({ kind: "suspendedPendingReinit", reinit }));
        case "removedFromGroup":
            return succeedDecoder({ kind: "removedFromGroup" });
        default:
            return failDecoder();
    }
});
//# sourceMappingURL=groupActiveState.js.map