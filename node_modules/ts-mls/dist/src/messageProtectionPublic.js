import { createMembershipTag, verifyMembershipTag, } from "./authenticatedContent.js";
import { signFramedContentApplicationOrProposal, toTbs, verifyFramedContentSignature, } from "./framedContent.js";
import { CryptoVerificationError, UsageError } from "./mlsError.js";
import { findSignaturePublicKey } from "./publicMessage.js";
export async function protectProposalPublic(signKey, membershipKey, groupContext, authenticatedData, proposal, leafIndex, cs) {
    const framedContent = {
        groupId: groupContext.groupId,
        epoch: groupContext.epoch,
        sender: { senderType: "member", leafIndex },
        contentType: "proposal",
        authenticatedData,
        proposal,
    };
    const tbs = {
        protocolVersion: groupContext.version,
        wireformat: "mls_public_message",
        content: framedContent,
        senderType: "member",
        context: groupContext,
    };
    const auth = await signFramedContentApplicationOrProposal(signKey, tbs, cs);
    const authenticatedContent = {
        wireformat: "mls_public_message",
        content: framedContent,
        auth,
    };
    const msg = await protectPublicMessage(membershipKey, groupContext, authenticatedContent, cs);
    return { publicMessage: msg };
}
export async function protectExternalProposalPublic(signKey, groupContext, authenticatedData, proposal, sender, cs) {
    const framedContent = {
        groupId: groupContext.groupId,
        epoch: groupContext.epoch,
        sender,
        contentType: "proposal",
        authenticatedData,
        proposal,
    };
    const tbs = {
        protocolVersion: groupContext.version,
        wireformat: "mls_public_message",
        content: framedContent,
        senderType: sender.senderType,
        context: groupContext,
    };
    const auth = await signFramedContentApplicationOrProposal(signKey, tbs, cs);
    const msg = {
        content: framedContent,
        auth,
        senderType: sender.senderType,
    };
    return { publicMessage: msg };
}
export async function protectPublicMessage(membershipKey, groupContext, content, cs) {
    if (content.content.contentType === "application")
        throw new UsageError("Can't make an application message public");
    if (content.content.sender.senderType == "member") {
        const authenticatedContent = {
            contentTbs: toTbs(content.content, "mls_public_message", groupContext),
            auth: content.auth,
        };
        const tag = await createMembershipTag(membershipKey, authenticatedContent, cs.hash);
        return {
            content: content.content,
            auth: content.auth,
            senderType: "member",
            membershipTag: tag,
        };
    }
    return {
        content: content.content,
        auth: content.auth,
        senderType: content.content.sender.senderType,
    };
}
export async function unprotectPublicMessage(membershipKey, groupContext, ratchetTree, msg, cs, overrideSignatureKey) {
    if (msg.content.contentType === "application")
        throw new UsageError("Can't make an application message public");
    if (msg.senderType === "member") {
        const authenticatedContent = {
            contentTbs: toTbs(msg.content, "mls_public_message", groupContext),
            auth: msg.auth,
        };
        if (!(await verifyMembershipTag(membershipKey, authenticatedContent, msg.membershipTag, cs.hash)))
            throw new CryptoVerificationError("Could not verify membership");
    }
    const signaturePublicKey = overrideSignatureKey !== undefined
        ? overrideSignatureKey
        : findSignaturePublicKey(ratchetTree, groupContext, msg.content);
    const signatureValid = await verifyFramedContentSignature(signaturePublicKey, "mls_public_message", msg.content, msg.auth, groupContext, cs.signature);
    if (!signatureValid)
        throw new CryptoVerificationError("Signature invalid");
    return {
        wireformat: "mls_public_message",
        content: msg.content,
        auth: msg.auth,
    };
}
//# sourceMappingURL=messageProtectionPublic.js.map