import { flatMapDecoder, mapDecoder, mapDecoders, succeedDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode, encVoid } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeExternalSender } from "./externalSender.js";
import { decodeFramedContent, decodeFramedContentAuthData, framedContentEncoder, framedContentAuthDataEncoder, } from "./framedContent.js";
import { CodecError, ValidationError } from "./mlsError.js";
import { getSignaturePublicKeyFromLeafIndex } from "./ratchetTree.js";
import { toLeafIndex } from "./treemath.js";
export const publicMessageInfoEncoder = (info) => {
    switch (info.senderType) {
        case "member":
            return varLenDataEncoder(info.membershipTag);
        case "external":
        case "new_member_proposal":
        case "new_member_commit":
            return encVoid;
    }
};
export const encodePublicMessageInfo = encode(publicMessageInfoEncoder);
export function decodePublicMessageInfo(senderType) {
    switch (senderType) {
        case "member":
            return mapDecoder(decodeVarLenData, (membershipTag) => ({
                senderType,
                membershipTag,
            }));
        case "external":
        case "new_member_proposal":
        case "new_member_commit":
            return succeedDecoder({ senderType });
    }
}
export const publicMessageEncoder = contramapBufferEncoders([framedContentEncoder, framedContentAuthDataEncoder, publicMessageInfoEncoder], (msg) => [msg.content, msg.auth, msg]);
export const encodePublicMessage = encode(publicMessageEncoder);
export const decodePublicMessage = flatMapDecoder(decodeFramedContent, (content) => mapDecoders([decodeFramedContentAuthData(content.contentType), decodePublicMessageInfo(content.sender.senderType)], (auth, info) => ({
    ...info,
    content,
    auth,
})));
export function findSignaturePublicKey(ratchetTree, groupContext, framedContent) {
    switch (framedContent.sender.senderType) {
        case "member":
            return getSignaturePublicKeyFromLeafIndex(ratchetTree, toLeafIndex(framedContent.sender.leafIndex));
        case "external": {
            const sender = senderFromExtension(groupContext.extensions, framedContent.sender.senderIndex);
            if (sender === undefined)
                throw new ValidationError("Received external but no external_sender extension");
            return sender.signaturePublicKey;
        }
        case "new_member_proposal":
            if (framedContent.contentType !== "proposal")
                throw new ValidationError("Received new_member_proposal but contentType is not proposal");
            if (framedContent.proposal.proposalType !== "add")
                throw new ValidationError("Received new_member_proposal but proposalType was not add");
            return framedContent.proposal.add.keyPackage.leafNode.signaturePublicKey;
        case "new_member_commit": {
            if (framedContent.contentType !== "commit")
                throw new ValidationError("Received new_member_commit but contentType is not commit");
            if (framedContent.commit.path === undefined)
                throw new ValidationError("Commit contains no update path");
            return framedContent.commit.path.leafNode.signaturePublicKey;
        }
    }
}
export function senderFromExtension(extensions, senderIndex) {
    const externalSenderExtensions = extensions.filter((ex) => ex.extensionType === "external_senders");
    const externalSenderExtension = externalSenderExtensions[senderIndex];
    if (externalSenderExtension !== undefined) {
        const externalSender = decodeExternalSender(externalSenderExtension.extensionData, 0);
        if (externalSender === undefined)
            throw new CodecError("Could not decode ExternalSender");
        return externalSender[0];
    }
}
//# sourceMappingURL=publicMessage.js.map