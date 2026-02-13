import { mapDecoder } from "./tlsDecoder.js";
import { contramapBufferEncoder, encode } from "./tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./variableLength.js";
export const stringEncoder = contramapBufferEncoder(varLenDataEncoder, (s) => new TextEncoder().encode(s));
export const encodeString = encode(stringEncoder);
export const decodeString = mapDecoder(decodeVarLenData, (u) => new TextDecoder().decode(u));
//# sourceMappingURL=string.js.map