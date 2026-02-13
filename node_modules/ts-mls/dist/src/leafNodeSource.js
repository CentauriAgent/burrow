import { decodeUint8, uint8Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
const leafNodeSources = {
    key_package: 1,
    update: 2,
    commit: 3,
};
export const leafNodeSourceEncoder = contramapBufferEncoder(uint8Encoder, (t) => leafNodeSources[t]);
export const encodeLeafNodeSource = encode(leafNodeSourceEncoder);
export const decodeLeafNodeSource = mapDecoderOption(decodeUint8, enumNumberToKey(leafNodeSources));
//# sourceMappingURL=leafNodeSource.js.map