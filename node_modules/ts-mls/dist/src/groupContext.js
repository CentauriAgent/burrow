import { decodeUint64, uint64Encoder } from "./codec/number.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { ciphersuiteEncoder, decodeCiphersuite } from "./crypto/ciphersuite.js";
import { expandWithLabel } from "./crypto/kdf.js";
import { decodeExtension, extensionEncoder } from "./extension.js";
import { decodeProtocolVersion, protocolVersionEncoder } from "./protocolVersion.js";
export const groupContextEncoder = contramapBufferEncoders([
    protocolVersionEncoder,
    ciphersuiteEncoder,
    varLenDataEncoder, // groupId
    uint64Encoder, // epoch
    varLenDataEncoder, // treeHash
    varLenDataEncoder, // confirmedTranscriptHash
    varLenTypeEncoder(extensionEncoder),
], (gc) => [gc.version, gc.cipherSuite, gc.groupId, gc.epoch, gc.treeHash, gc.confirmedTranscriptHash, gc.extensions]);
export const encodeGroupContext = encode(groupContextEncoder);
export const decodeGroupContext = mapDecoders([
    decodeProtocolVersion,
    decodeCiphersuite,
    decodeVarLenData, // groupId
    decodeUint64, // epoch
    decodeVarLenData, // treeHash
    decodeVarLenData, // confirmedTranscriptHash
    decodeVarLenType(decodeExtension),
], (version, cipherSuite, groupId, epoch, treeHash, confirmedTranscriptHash, extensions) => ({
    version,
    cipherSuite,
    groupId,
    epoch,
    treeHash,
    confirmedTranscriptHash,
    extensions,
}));
export async function extractEpochSecret(context, joinerSecret, kdf, pskSecret) {
    const psk = pskSecret === undefined ? new Uint8Array(kdf.size) : pskSecret;
    const extracted = await kdf.extract(joinerSecret, psk);
    return expandWithLabel(extracted, "epoch", encode(groupContextEncoder)(context), kdf.size, kdf);
}
export async function extractJoinerSecret(context, previousInitSecret, commitSecret, kdf) {
    const extracted = await kdf.extract(previousInitSecret, commitSecret);
    return expandWithLabel(extracted, "joiner", encode(groupContextEncoder)(context), kdf.size, kdf);
}
//# sourceMappingURL=groupContext.js.map