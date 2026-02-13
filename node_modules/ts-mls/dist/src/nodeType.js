import { decodeUint8, uint8Encoder } from "./codec/number.js";
import { mapDecoderOption } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./codec/tlsEncoder.js";
import { enumNumberToKey } from "./util/enumHelpers.js";
const nodeTypes = {
    leaf: 1,
    parent: 2,
};
export const nodeTypeEncoder = contramapBufferEncoder(uint8Encoder, (t) => nodeTypes[t]);
export const encodeNodeType = encode(nodeTypeEncoder);
export const decodeNodeType = mapDecoderOption(decodeUint8, enumNumberToKey(nodeTypes));
//# sourceMappingURL=nodeType.js.map