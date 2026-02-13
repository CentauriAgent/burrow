import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { varLenDataEncoder, decodeVarLenData } from "./codec/variableLength.js";
export const hpkeCiphertextEncoder = contramapBufferEncoders([varLenDataEncoder, varLenDataEncoder], (egs) => [egs.kemOutput, egs.ciphertext]);
export const encodeHpkeCiphertext = encode(hpkeCiphertextEncoder);
export const decodeHpkeCiphertext = mapDecoders([decodeVarLenData, decodeVarLenData], (kemOutput, ciphertext) => ({ kemOutput, ciphertext }));
//# sourceMappingURL=hpkeCiphertext.js.map