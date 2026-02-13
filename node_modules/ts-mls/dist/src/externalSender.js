import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeCredential, credentialEncoder } from "./credential.js";
export const externalSenderEncoder = contramapBufferEncoders([varLenDataEncoder, credentialEncoder], (e) => [e.signaturePublicKey, e.credential]);
/** @public */
export const encodeExternalSender = encode(externalSenderEncoder);
/** @public */
export const decodeExternalSender = mapDecoders([decodeVarLenData, decodeCredential], (signaturePublicKey, credential) => ({ signaturePublicKey, credential }));
//# sourceMappingURL=externalSender.js.map