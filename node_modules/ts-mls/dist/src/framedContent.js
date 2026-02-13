import { decodeUint64, uint64Encoder } from "./codec/number.js";
import { flatMapDecoder, mapDecoder, mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders, encode, encVoid, } from "./codec/tlsEncoder.js";
import { decodeVarLenData, varLenDataEncoder } from "./codec/variableLength.js";
import { decodeCommit, commitEncoder } from "./commit.js";
import { contentTypeEncoder, decodeContentType } from "./contentType.js";
import { signWithLabel, verifyWithLabel } from "./crypto/signature.js";
import { groupContextEncoder } from "./groupContext.js";
import { wireformatEncoder } from "./wireformat.js";
import { decodeProposal, proposalEncoder } from "./proposal.js";
import { protocolVersionEncoder } from "./protocolVersion.js";
import { decodeSender, senderEncoder, } from "./sender.js";
export const framedContentApplicationDataEncoder = contramapBufferEncoders([contentTypeEncoder, varLenDataEncoder], (f) => [f.contentType, f.applicationData]);
export const encodeFramedContentApplicationData = encode(framedContentApplicationDataEncoder);
export const framedContentProposalDataEncoder = contramapBufferEncoders([contentTypeEncoder, proposalEncoder], (f) => [f.contentType, f.proposal]);
export const encodeFramedContentProposalData = encode(framedContentProposalDataEncoder);
export const framedContentCommitDataEncoder = contramapBufferEncoders([contentTypeEncoder, commitEncoder], (f) => [f.contentType, f.commit]);
export const encodeFramedContentCommitData = encode(framedContentCommitDataEncoder);
export const framedContentInfoEncoder = (fc) => {
    switch (fc.contentType) {
        case "application":
            return framedContentApplicationDataEncoder(fc);
        case "proposal":
            return framedContentProposalDataEncoder(fc);
        case "commit":
            return framedContentCommitDataEncoder(fc);
    }
};
export const encodeFramedContentInfo = encode(framedContentInfoEncoder);
export const decodeFramedContentApplicationData = mapDecoder(decodeVarLenData, (applicationData) => ({ contentType: "application", applicationData }));
export const decodeFramedContentProposalData = mapDecoder(decodeProposal, (proposal) => ({ contentType: "proposal", proposal }));
export const decodeFramedContentCommitData = mapDecoder(decodeCommit, (commit) => ({
    contentType: "commit",
    commit,
}));
export const decodeFramedContentInfo = flatMapDecoder(decodeContentType, (contentType) => {
    switch (contentType) {
        case "application":
            return decodeFramedContentApplicationData;
        case "proposal":
            return decodeFramedContentProposalData;
        case "commit":
            return decodeFramedContentCommitData;
    }
});
export function toTbs(content, wireformat, context) {
    return { protocolVersion: context.version, wireformat, content, senderType: content.sender.senderType, context };
}
export const framedContentEncoder = contramapBufferEncoders([varLenDataEncoder, uint64Encoder, senderEncoder, varLenDataEncoder, framedContentInfoEncoder], (fc) => [fc.groupId, fc.epoch, fc.sender, fc.authenticatedData, fc]);
export const encodeFramedContent = encode(framedContentEncoder);
export const decodeFramedContent = mapDecoders([decodeVarLenData, decodeUint64, decodeSender, decodeVarLenData, decodeFramedContentInfo], (groupId, epoch, sender, authenticatedData, info) => ({
    groupId,
    epoch,
    sender,
    authenticatedData,
    ...info,
}));
export const senderInfoEncoder = (info) => {
    switch (info.senderType) {
        case "member":
        case "new_member_commit":
            return groupContextEncoder(info.context);
        case "external":
        case "new_member_proposal":
            return encVoid;
    }
};
export const encodeSenderInfo = encode(senderInfoEncoder);
export const framedContentTBSEncoder = contramapBufferEncoders([protocolVersionEncoder, wireformatEncoder, framedContentEncoder, senderInfoEncoder], (f) => [f.protocolVersion, f.wireformat, f.content, f]);
export const encodeFramedContentTBS = encode(framedContentTBSEncoder);
const encodeFramedContentAuthDataContent = (authData) => {
    switch (authData.contentType) {
        case "commit":
            return encodeFramedContentAuthDataCommit(authData);
        case "application":
        case "proposal":
            return encVoid;
    }
};
const encodeFramedContentAuthDataCommit = contramapBufferEncoder(varLenDataEncoder, (data) => data.confirmationTag);
export const framedContentAuthDataEncoder = contramapBufferEncoders([varLenDataEncoder, encodeFramedContentAuthDataContent], (d) => [d.signature, d]);
export const encodeFramedContentAuthData = encode(framedContentAuthDataEncoder);
export const decodeFramedContentAuthDataCommit = mapDecoder(decodeVarLenData, (confirmationTag) => ({
    contentType: "commit",
    confirmationTag,
}));
export function decodeFramedContentAuthData(contentType) {
    switch (contentType) {
        case "commit":
            return mapDecoders([decodeVarLenData, decodeFramedContentAuthDataCommit], (signature, commitData) => ({
                signature,
                ...commitData,
            }));
        case "application":
        case "proposal":
            return mapDecoder(decodeVarLenData, (signature) => ({
                signature,
                contentType,
            }));
    }
}
export async function verifyFramedContentSignature(signKey, wireformat, content, auth, context, s) {
    return verifyWithLabel(signKey, "FramedContentTBS", encode(framedContentTBSEncoder)(toTbs(content, wireformat, context)), auth.signature, s);
}
export function signFramedContentTBS(signKey, tbs, s) {
    return signWithLabel(signKey, "FramedContentTBS", encode(framedContentTBSEncoder)(tbs), s);
}
export async function signFramedContentApplicationOrProposal(signKey, tbs, cs) {
    const signature = await signFramedContentTBS(signKey, tbs, cs.signature);
    return {
        contentType: tbs.content.contentType,
        signature,
    };
}
export function createConfirmationTag(confirmationKey, confirmedTranscriptHash, h) {
    return h.mac(confirmationKey, confirmedTranscriptHash);
}
export function verifyConfirmationTag(confirmationKey, tag, confirmedTranscriptHash, h) {
    return h.verifyMac(confirmationKey, tag, confirmedTranscriptHash);
}
export async function createContentCommitSignature(groupContext, wireformat, c, sender, authenticatedData, signKey, s) {
    const tbs = {
        protocolVersion: groupContext.version,
        wireformat,
        content: {
            contentType: "commit",
            commit: c,
            groupId: groupContext.groupId,
            epoch: groupContext.epoch,
            sender,
            authenticatedData,
        },
        senderType: "member",
        context: groupContext,
    };
    const signature = await signFramedContentTBS(signKey, tbs, s);
    return { framedContent: tbs.content, signature };
}
//# sourceMappingURL=framedContent.js.map