import { makeProposalRef } from "./authenticatedContent.js";
import { signFramedContentApplicationOrProposal, verifyFramedContentSignature, } from "./framedContent.js";
import { decodePrivateMessageContent, decryptSenderData, encodePrivateMessageContent, encryptSenderData, privateContentAADEncoder, toAuthenticatedContent, } from "./privateMessage.js";
import { consumeRatchet, ratchetToGeneration } from "./secretTree.js";
import { getSignaturePublicKeyFromLeafIndex } from "./ratchetTree.js";
import { leafToNodeIndex, toLeafIndex } from "./treemath.js";
import { CryptoVerificationError, CodecError, ValidationError, InternalError } from "./mlsError.js";
import { encode } from "./codec/tlsEncoder.js";
export async function protectApplicationData(signKey, senderDataSecret, applicationData, authenticatedData, groupContext, secretTree, leafIndex, paddingConfig, cs) {
    const tbs = {
        protocolVersion: groupContext.version,
        wireformat: "mls_private_message",
        content: {
            contentType: "application",
            applicationData,
            groupId: groupContext.groupId,
            epoch: groupContext.epoch,
            sender: {
                senderType: "member",
                leafIndex: leafIndex,
            },
            authenticatedData,
        },
        senderType: "member",
        context: groupContext,
    };
    const auth = await signFramedContentApplicationOrProposal(signKey, tbs, cs);
    const content = {
        ...tbs.content,
        auth,
    };
    const result = await protect(senderDataSecret, authenticatedData, groupContext, secretTree, content, leafIndex, paddingConfig, cs);
    return { newSecretTree: result.tree, privateMessage: result.privateMessage, consumed: result.consumed };
}
export async function protectProposal(signKey, senderDataSecret, p, authenticatedData, groupContext, secretTree, leafIndex, paddingConfig, cs) {
    const tbs = {
        protocolVersion: groupContext.version,
        wireformat: "mls_private_message",
        content: {
            contentType: "proposal",
            proposal: p,
            groupId: groupContext.groupId,
            epoch: groupContext.epoch,
            sender: {
                senderType: "member",
                leafIndex,
            },
            authenticatedData,
        },
        senderType: "member",
        context: groupContext,
    };
    const auth = await signFramedContentApplicationOrProposal(signKey, tbs, cs);
    const content = { ...tbs.content, auth };
    const protectResult = await protect(senderDataSecret, authenticatedData, groupContext, secretTree, content, leafIndex, paddingConfig, cs);
    const newSecretTree = protectResult.tree;
    const authenticatedContent = {
        wireformat: "mls_private_message",
        content,
        auth,
    };
    const proposalRef = await makeProposalRef(authenticatedContent, cs.hash);
    return { privateMessage: protectResult.privateMessage, newSecretTree, proposalRef, consumed: protectResult.consumed };
}
export async function protect(senderDataSecret, authenticatedData, groupContext, secretTree, content, leafIndex, config, cs) {
    const node = secretTree[leafToNodeIndex(toLeafIndex(leafIndex))];
    if (node === undefined)
        throw new InternalError("Bad node index for secret tree");
    const { newTree, generation, reuseGuard, nonce, key, consumed } = await consumeRatchet(secretTree, leafToNodeIndex(toLeafIndex(leafIndex)), content.contentType, cs);
    const aad = {
        groupId: groupContext.groupId,
        epoch: groupContext.epoch,
        contentType: content.contentType,
        authenticatedData: authenticatedData,
    };
    const ciphertext = await cs.hpke.encryptAead(key, nonce, encode(privateContentAADEncoder)(aad), encodePrivateMessageContent(config)(content));
    const senderData = {
        leafIndex,
        generation,
        reuseGuard,
    };
    const senderAad = {
        groupId: groupContext.groupId,
        epoch: groupContext.epoch,
        contentType: content.contentType,
    };
    const encryptedSenderData = await encryptSenderData(senderDataSecret, senderData, senderAad, ciphertext, cs);
    return {
        privateMessage: {
            groupId: groupContext.groupId,
            epoch: groupContext.epoch,
            encryptedSenderData,
            contentType: content.contentType,
            authenticatedData,
            ciphertext,
        },
        tree: newTree,
        consumed,
    };
}
export async function unprotectPrivateMessage(senderDataSecret, msg, secretTree, ratchetTree, groupContext, config, cs, overrideSignatureKey) {
    const senderData = await decryptSenderData(msg, senderDataSecret, cs);
    if (senderData === undefined)
        throw new CodecError("Could not decode senderdata");
    validateSenderData(senderData, ratchetTree);
    const { key, nonce, newTree, consumed } = await ratchetToGeneration(secretTree, senderData, msg.contentType, config, cs);
    const aad = {
        groupId: msg.groupId,
        epoch: msg.epoch,
        contentType: msg.contentType,
        authenticatedData: msg.authenticatedData,
    };
    const decrypted = await cs.hpke.decryptAead(key, nonce, encode(privateContentAADEncoder)(aad), msg.ciphertext);
    const pmc = decodePrivateMessageContent(msg.contentType)(decrypted, 0)?.[0];
    if (pmc === undefined)
        throw new CodecError("Could not decode PrivateMessageContent");
    const content = toAuthenticatedContent(pmc, msg, senderData.leafIndex);
    const signaturePublicKey = overrideSignatureKey !== undefined
        ? overrideSignatureKey
        : getSignaturePublicKeyFromLeafIndex(ratchetTree, toLeafIndex(senderData.leafIndex));
    const signatureValid = await verifyFramedContentSignature(signaturePublicKey, "mls_private_message", content.content, content.auth, groupContext, cs.signature);
    if (!signatureValid)
        throw new CryptoVerificationError("Signature invalid");
    return { tree: newTree, content, consumed };
}
export function validateSenderData(senderData, tree) {
    if (tree[leafToNodeIndex(toLeafIndex(senderData.leafIndex))]?.nodeType !== "leaf")
        return new ValidationError("SenderData did not point to a non-blank leaf node");
}
//# sourceMappingURL=messageProtection.js.map