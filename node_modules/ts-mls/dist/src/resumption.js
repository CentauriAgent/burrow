import { makePskIndex, createGroup, joinGroup } from "./clientState.js";
import { createCommit } from "./createCommit.js";
import { getCiphersuiteFromName } from "./crypto/ciphersuite.js";
import { getCiphersuiteImpl } from "./crypto/getCiphersuiteImpl.js";
import { defaultCryptoProvider } from "./crypto/implementation/default/provider.js";
import { UsageError } from "./mlsError.js";
/** @public */
export async function reinitGroup(state, groupId, version, cipherSuite, extensions, cs) {
    const reinitProposal = {
        proposalType: "reinit",
        reinit: {
            groupId,
            version,
            cipherSuite,
            extensions,
        },
    };
    return createCommit({
        state,
        pskIndex: makePskIndex(state, {}),
        cipherSuite: cs,
    }, {
        extraProposals: [reinitProposal],
    });
}
/** @public */
export async function reinitCreateNewGroup(state, keyPackage, privateKeyPackage, memberKeyPackages, groupId, cipherSuite, extensions, provider = defaultCryptoProvider) {
    const cs = await getCiphersuiteImpl(getCiphersuiteFromName(cipherSuite), provider);
    const newGroup = await createGroup(groupId, keyPackage, privateKeyPackage, extensions, cs);
    const addProposals = memberKeyPackages.map((kp) => ({
        proposalType: "add",
        add: { keyPackage: kp },
    }));
    const psk = makeResumptionPsk(state, "reinit", cs);
    const resumptionPsk = {
        proposalType: "psk",
        psk: {
            preSharedKeyId: psk.id,
        },
    };
    return createCommit({
        state: newGroup,
        pskIndex: makePskIndex(state, {}),
        cipherSuite: cs,
    }, {
        extraProposals: [...addProposals, resumptionPsk],
    });
}
export function makeResumptionPsk(state, usage, cs) {
    const secret = state.keySchedule.resumptionPsk;
    const pskNonce = cs.rng.randomBytes(cs.kdf.size);
    const psk = {
        pskEpoch: state.groupContext.epoch,
        pskGroupId: state.groupContext.groupId,
        psktype: "resumption",
        pskNonce,
        usage,
    };
    return { id: psk, secret };
}
/** @public */
export async function branchGroup(state, keyPackage, privateKeyPackage, memberKeyPackages, newGroupId, cs) {
    const resumptionPsk = makeResumptionPsk(state, "branch", cs);
    const pskSearch = makePskIndex(state, {});
    const newGroup = await createGroup(newGroupId, keyPackage, privateKeyPackage, state.groupContext.extensions, cs);
    const addMemberProposals = memberKeyPackages.map((kp) => ({
        proposalType: "add",
        add: {
            keyPackage: kp,
        },
    }));
    const branchPskProposal = {
        proposalType: "psk",
        psk: {
            preSharedKeyId: resumptionPsk.id,
        },
    };
    return createCommit({
        state: newGroup,
        pskIndex: pskSearch,
        cipherSuite: cs,
    }, {
        extraProposals: [...addMemberProposals, branchPskProposal],
    });
}
/** @public */
export async function joinGroupFromBranch(oldState, welcome, keyPackage, privateKeyPackage, ratchetTree, cs) {
    const pskSearch = makePskIndex(oldState, {});
    return await joinGroup(welcome, keyPackage, privateKeyPackage, pskSearch, cs, ratchetTree, oldState);
}
/** @public */
export async function joinGroupFromReinit(suspendedState, welcome, keyPackage, privateKeyPackage, ratchetTree, provider = defaultCryptoProvider) {
    const pskSearch = makePskIndex(suspendedState, {});
    if (suspendedState.groupActiveState.kind !== "suspendedPendingReinit")
        throw new UsageError("Cannot reinit because no init proposal found in last commit");
    const cs = await getCiphersuiteImpl(getCiphersuiteFromName(suspendedState.groupActiveState.reinit.cipherSuite), provider);
    return await joinGroup(welcome, keyPackage, privateKeyPackage, pskSearch, cs, ratchetTree, suspendedState);
}
//# sourceMappingURL=resumption.js.map