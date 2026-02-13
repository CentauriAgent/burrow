import { decodeOptional, optionalEncoder } from "./codec/optional.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { decodePskId, pskIdEncoder } from "./presharedkey.js";
export const groupSecretsEncoder = contramapBufferEncoders([varLenDataEncoder, optionalEncoder(varLenDataEncoder), varLenTypeEncoder(pskIdEncoder)], (gs) => [gs.joinerSecret, gs.pathSecret, gs.psks]);
export const encodeGroupSecrets = encode(groupSecretsEncoder);
export const decodeGroupSecrets = mapDecoders([decodeVarLenData, decodeOptional(decodeVarLenData), decodeVarLenType(decodePskId)], (joinerSecret, pathSecret, psks) => ({ joinerSecret, pathSecret, psks }));
//# sourceMappingURL=groupSecrets.js.map