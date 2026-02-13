import { decodeUint16, uint16Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
/** @public */
export const defaultExtensionTypes = {
    application_id: 1,
    ratchet_tree: 2,
    required_capabilities: 3,
    external_pub: 4,
    external_senders: 5,
};
export const defaultExtensionTypeEncoder = contramapBufferEncoder(uint16Encoder, (n) => defaultExtensionTypes[n]);
export const encodeDefaultExtensionType = encode(defaultExtensionTypeEncoder);
export const decodeDefaultExtensionType = mapDecoderOption(decodeUint16, enumNumberToKey(defaultExtensionTypes));
//# sourceMappingURL=defaultExtensionType.js.map