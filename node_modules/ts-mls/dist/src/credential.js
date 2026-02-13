import { flatMapDecoder, mapDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { decodeCredentialType, credentialTypeEncoder } from "./credentialType.js";
export const credentialBasicEncoder = contramapBufferEncoders([credentialTypeEncoder, varLenDataEncoder], (c) => [c.credentialType, c.identity]);
export const encodeCredentialBasic = encode(credentialBasicEncoder);
export const credentialX509Encoder = contramapBufferEncoders([credentialTypeEncoder, varLenTypeEncoder(varLenDataEncoder)], (c) => [c.credentialType, c.certificates]);
export const encodeCredentialX509 = encode(credentialX509Encoder);
export const credentialCustomEncoder = contramapBufferEncoders([credentialTypeEncoder, varLenDataEncoder], (c) => [c.credentialType, c.data]);
export const encodeCredentialCustom = encode(credentialCustomEncoder);
export const credentialEncoder = (c) => {
    switch (c.credentialType) {
        case "basic":
            return credentialBasicEncoder(c);
        case "x509":
            return credentialX509Encoder(c);
        default:
            return credentialCustomEncoder(c);
    }
};
export const encodeCredential = encode(credentialEncoder);
const decodeCredentialBasic = mapDecoder(decodeVarLenData, (identity) => ({
    credentialType: "basic",
    identity,
}));
const decodeCredentialX509 = mapDecoder(decodeVarLenType(decodeVarLenData), (certificates) => ({ credentialType: "x509", certificates }));
export const decodeCredential = flatMapDecoder(decodeCredentialType, (credentialType) => {
    switch (credentialType) {
        case "basic":
            return decodeCredentialBasic;
        case "x509":
            return decodeCredentialX509;
    }
});
//# sourceMappingURL=credential.js.map