import { decodeUint64, uint64Encoder } from "./codec/number.js";
import { mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeCommit, commitEncoder } from "./commit.js";
import { contentTypeEncoder, decodeContentType } from "./contentType.js";
import { decodeFramedContentAuthDataCommit, framedContentAuthDataEncoder, } from "./framedContent.js";
import { byteLengthToPad } from "./paddingConfig.js";
import { decodeProposal, proposalEncoder } from "./proposal.js";
import { decodeSenderData, senderDataEncoder, senderDataAADEncoder, expandSenderDataKey, expandSenderDataNonce, } from "./sender.js";
export const privateMessageEncoder = contramapBufferEncoders([varLenDataEncoder, uint64Encoder, contentTypeEncoder, varLenDataEncoder, varLenDataEncoder, varLenDataEncoder], (msg) => [msg.groupId, msg.epoch, msg.contentType, msg.authenticatedData, msg.encryptedSenderData, msg.ciphertext]);
export const encodePrivateMessage = encode(privateMessageEncoder);
export const decodePrivateMessage = mapDecoders([decodeVarLenData, decodeUint64, decodeContentType, decodeVarLenData, decodeVarLenData, decodeVarLenData], (groupId, epoch, contentType, authenticatedData, encryptedSenderData, ciphertext) => ({
    groupId,
    epoch,
    contentType,
    authenticatedData,
    encryptedSenderData,
    ciphertext,
}));
export const privateContentAADEncoder = contramapBufferEncoders([varLenDataEncoder, uint64Encoder, contentTypeEncoder, varLenDataEncoder], (aad) => [aad.groupId, aad.epoch, aad.contentType, aad.authenticatedData]);
export const encodePrivateContentAAD = encode(privateContentAADEncoder);
export const decodePrivateContentAAD = mapDecoders([decodeVarLenData, decodeUint64, decodeContentType, decodeVarLenData], (groupId, epoch, contentType, authenticatedData) => ({
    groupId,
    epoch,
    contentType,
    authenticatedData,
}));
export function decodePrivateMessageContent(contentType) {
    switch (contentType) {
        case "application":
            return decoderWithPadding(mapDecoders([decodeVarLenData, decodeVarLenData], (applicationData, signature) => ({
                contentType,
                applicationData,
                auth: { contentType, signature },
            })));
        case "proposal":
            return decoderWithPadding(mapDecoders([decodeProposal, decodeVarLenData], (proposal, signature) => ({
                contentType,
                proposal,
                auth: { contentType, signature },
            })));
        case "commit":
            return decoderWithPadding(mapDecoders([decodeCommit, decodeVarLenData, decodeFramedContentAuthDataCommit], (commit, signature, auth) => ({
                contentType,
                commit,
                auth: { ...auth, signature, contentType },
            })));
    }
}
export function privateMessageContentEncoder(config) {
    return (msg) => {
        switch (msg.contentType) {
            case "application":
                return encoderWithPadding(contramapBufferEncoders([varLenDataEncoder, framedContentAuthDataEncoder], (m) => [m.applicationData, m.auth]), config)(msg);
            case "proposal":
                return encoderWithPadding(contramapBufferEncoders([proposalEncoder, framedContentAuthDataEncoder], (m) => [m.proposal, m.auth]), config)(msg);
            case "commit":
                return encoderWithPadding(contramapBufferEncoders([commitEncoder, framedContentAuthDataEncoder], (m) => [m.commit, m.auth]), config)(msg);
        }
    };
}
export function encodePrivateMessageContent(config) {
    return encode(privateMessageContentEncoder(config));
}
export async function decryptSenderData(msg, senderDataSecret, cs) {
    const key = await expandSenderDataKey(cs, senderDataSecret, msg.ciphertext);
    const nonce = await expandSenderDataNonce(cs, senderDataSecret, msg.ciphertext);
    const aad = {
        groupId: msg.groupId,
        epoch: msg.epoch,
        contentType: msg.contentType,
    };
    const decrypted = await cs.hpke.decryptAead(key, nonce, encode(senderDataAADEncoder)(aad), msg.encryptedSenderData);
    return decodeSenderData(decrypted, 0)?.[0];
}
export async function encryptSenderData(senderDataSecret, senderData, aad, ciphertext, cs) {
    const key = await expandSenderDataKey(cs, senderDataSecret, ciphertext);
    const nonce = await expandSenderDataNonce(cs, senderDataSecret, ciphertext);
    return await cs.hpke.encryptAead(key, nonce, encode(senderDataAADEncoder)(aad), encode(senderDataEncoder)(senderData));
}
export function toAuthenticatedContent(content, msg, senderLeafIndex) {
    return {
        wireformat: "mls_private_message",
        content: {
            groupId: msg.groupId,
            epoch: msg.epoch,
            sender: {
                senderType: "member",
                leafIndex: senderLeafIndex,
            },
            authenticatedData: msg.authenticatedData,
            ...content,
        },
        auth: content.auth,
    };
}
function encoderWithPadding(encoder, config) {
    return (t) => {
        const [len, write] = encoder(t);
        const totalLength = len + byteLengthToPad(len, config);
        return [
            totalLength,
            (offset, buffer) => {
                write(offset, buffer);
            },
        ];
    };
}
function decoderWithPadding(decoder) {
    return (bytes, offset) => {
        const result = decoder(bytes, offset);
        if (result === undefined)
            return undefined;
        const [decoded, innerOffset] = result;
        const paddingBytes = bytes.subarray(offset + innerOffset, bytes.length);
        const allZeroes = paddingBytes.every((byte) => byte === 0);
        if (!allZeroes)
            return undefined;
        return [decoded, bytes.length];
    };
}
//# sourceMappingURL=privateMessage.js.map