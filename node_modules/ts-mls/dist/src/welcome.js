import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { ciphersuiteEncoder, decodeCiphersuite } from "./crypto/ciphersuite.js";
import { encryptWithLabel, decryptWithLabel } from "./crypto/hpke.js";
import { expandWithLabel } from "./crypto/kdf.js";
import { decodeGroupInfo, groupInfoEncoder, extractWelcomeSecret } from "./groupInfo.js";
import { decodeGroupSecrets, groupSecretsEncoder } from "./groupSecrets.js";
import { hpkeCiphertextEncoder, decodeHpkeCiphertext } from "./hpkeCiphertext.js";
import { ValidationError } from "./mlsError.js";
import { constantTimeEqual } from "./util/constantTimeCompare.js";
export const encryptedGroupSecretsEncoder = contramapBufferEncoders([varLenDataEncoder, hpkeCiphertextEncoder], (egs) => [egs.newMember, egs.encryptedGroupSecrets]);
export const encodeEncryptedGroupSecrets = encode(encryptedGroupSecretsEncoder);
export const decodeEncryptedGroupSecrets = mapDecoders([decodeVarLenData, decodeHpkeCiphertext], (newMember, encryptedGroupSecrets) => ({ newMember, encryptedGroupSecrets }));
export const welcomeEncoder = contramapBufferEncoders([ciphersuiteEncoder, varLenTypeEncoder(encryptedGroupSecretsEncoder), varLenDataEncoder], (welcome) => [welcome.cipherSuite, welcome.secrets, welcome.encryptedGroupInfo]);
export const encodeWelcome = encode(welcomeEncoder);
export const decodeWelcome = mapDecoders([decodeCiphersuite, decodeVarLenType(decodeEncryptedGroupSecrets), decodeVarLenData], (cipherSuite, secrets, encryptedGroupInfo) => ({ cipherSuite, secrets, encryptedGroupInfo }));
export function welcomeNonce(welcomeSecret, cs) {
    return expandWithLabel(welcomeSecret, "nonce", new Uint8Array(), cs.hpke.nonceLength, cs.kdf);
}
export function welcomeKey(welcomeSecret, cs) {
    return expandWithLabel(welcomeSecret, "key", new Uint8Array(), cs.hpke.keyLength, cs.kdf);
}
export async function encryptGroupInfo(groupInfo, welcomeSecret, cs) {
    const key = await welcomeKey(welcomeSecret, cs);
    const nonce = await welcomeNonce(welcomeSecret, cs);
    const encrypted = await cs.hpke.encryptAead(key, nonce, undefined, encode(groupInfoEncoder)(groupInfo));
    return encrypted;
}
export async function decryptGroupInfo(w, joinerSecret, pskSecret, cs) {
    const welcomeSecret = await extractWelcomeSecret(joinerSecret, pskSecret, cs.kdf);
    const key = await welcomeKey(welcomeSecret, cs);
    const nonce = await welcomeNonce(welcomeSecret, cs);
    const decrypted = await cs.hpke.decryptAead(key, nonce, undefined, w.encryptedGroupInfo);
    const decoded = decodeGroupInfo(decrypted, 0);
    return decoded?.[0];
}
export function encryptGroupSecrets(initKey, encryptedGroupInfo, groupSecrets, hpke) {
    return encryptWithLabel(initKey, "Welcome", encryptedGroupInfo, encode(groupSecretsEncoder)(groupSecrets), hpke);
}
export async function decryptGroupSecrets(initPrivateKey, keyPackageRef, welcome, hpke) {
    const secret = welcome.secrets.find((s) => constantTimeEqual(s.newMember, keyPackageRef));
    if (secret === undefined)
        throw new ValidationError("No matching secret found");
    const decrypted = await decryptWithLabel(initPrivateKey, "Welcome", welcome.encryptedGroupInfo, secret.encryptedGroupSecrets.kemOutput, secret.encryptedGroupSecrets.ciphertext, hpke);
    return decodeGroupSecrets(decrypted, 0)?.[0];
}
//# sourceMappingURL=welcome.js.map