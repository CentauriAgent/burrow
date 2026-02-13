import { extensionsSupportedByCapabilities } from "./extension.js";
import { decodeExternalSender } from "./externalSender.js";
import { protectExternalProposalPublic } from "./messageProtectionPublic.js";
import { UsageError, ValidationError } from "./mlsError.js";
import { constantTimeEqual } from "./util/constantTimeCompare.js";
/** @public */
export async function proposeAddExternal(groupInfo, keyPackage, privateKeyPackage, cs, authenticatedData = new Uint8Array()) {
    const allExtensionsSupported = extensionsSupportedByCapabilities(groupInfo.groupContext.extensions, keyPackage.leafNode.capabilities);
    if (!allExtensionsSupported)
        throw new UsageError("client does not support every extension in the GroupContext");
    const proposal = {
        proposalType: "add",
        add: {
            keyPackage,
        },
    };
    const result = await protectExternalProposalPublic(privateKeyPackage.signaturePrivateKey, groupInfo.groupContext, authenticatedData, proposal, { senderType: "new_member_proposal" }, cs);
    return {
        wireformat: "mls_public_message",
        version: groupInfo.groupContext.version,
        publicMessage: result.publicMessage,
    };
}
/** @public */
export async function proposeExternal(groupInfo, proposal, signaturePublicKey, signaturePrivateKey, cs, authenticatedData = new Uint8Array()) {
    const externalSenderExtensionIndex = groupInfo.groupContext.extensions.findIndex((ex) => {
        if (ex.extensionType !== "external_senders")
            return false;
        const decoded = decodeExternalSender(ex.extensionData, 0);
        if (decoded === undefined)
            throw new ValidationError("Could not decode external_sender extension");
        return constantTimeEqual(decoded[0].signaturePublicKey, signaturePublicKey);
    });
    if (externalSenderExtensionIndex === -1)
        throw new ValidationError("Could not find external_sender extension in groupContext.extensions");
    const result = await protectExternalProposalPublic(signaturePrivateKey, groupInfo.groupContext, authenticatedData, proposal, { senderType: "external", senderIndex: externalSenderExtensionIndex }, cs);
    return {
        wireformat: "mls_public_message",
        version: groupInfo.groupContext.version,
        publicMessage: result.publicMessage,
    };
}
//# sourceMappingURL=externalProposal.js.map