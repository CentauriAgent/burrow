import { checkCanSendApplicationMessages, processProposal } from "./clientState.js";
import { protectProposal, protectApplicationData } from "./messageProtection.js";
import { protectProposalPublic } from "./messageProtectionPublic.js";
import { addUnappliedProposal } from "./unappliedProposals.js";
/** @public */
export async function createProposal(state, publicMessage, proposal, cs, authenticatedData = new Uint8Array()) {
    if (publicMessage) {
        const result = await protectProposalPublic(state.signaturePrivateKey, state.keySchedule.membershipKey, state.groupContext, authenticatedData, proposal, state.privatePath.leafIndex, cs);
        const newState = await processProposal(state, { content: result.publicMessage.content, auth: result.publicMessage.auth, wireformat: "mls_public_message" }, proposal, cs.hash);
        return {
            newState,
            message: { wireformat: "mls_public_message", version: "mls10", publicMessage: result.publicMessage },
            consumed: [],
        };
    }
    else {
        const result = await protectProposal(state.signaturePrivateKey, state.keySchedule.senderDataSecret, proposal, authenticatedData, state.groupContext, state.secretTree, state.privatePath.leafIndex, state.clientConfig.paddingConfig, cs);
        const newState = {
            ...state,
            secretTree: result.newSecretTree,
            unappliedProposals: addUnappliedProposal(result.proposalRef, state.unappliedProposals, proposal, state.privatePath.leafIndex),
        };
        return {
            newState,
            message: { wireformat: "mls_private_message", version: "mls10", privateMessage: result.privateMessage },
            consumed: result.consumed,
        };
    }
}
/** @public */
export async function createApplicationMessage(state, message, cs, authenticatedData = new Uint8Array()) {
    checkCanSendApplicationMessages(state);
    const result = await protectApplicationData(state.signaturePrivateKey, state.keySchedule.senderDataSecret, message, authenticatedData, state.groupContext, state.secretTree, state.privatePath.leafIndex, state.clientConfig.paddingConfig, cs);
    return {
        newState: { ...state, secretTree: result.newSecretTree },
        privateMessage: result.privateMessage,
        consumed: result.consumed,
    };
}
//# sourceMappingURL=createMessage.js.map