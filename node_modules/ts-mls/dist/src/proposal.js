import { decodeUint16, decodeUint32, uint16Encoder, uint32Encoder } from "./codec/number.js";
import { flatMapDecoder, mapDecoder, mapDecoders, orDecoder } from "./codec/tlsDecoder.js";
import { contramapBufferEncoder, contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeVarLenData, decodeVarLenType, varLenDataEncoder, varLenTypeEncoder } from "./codec/variableLength.js";
import { ciphersuiteEncoder, decodeCiphersuite } from "./crypto/ciphersuite.js";
import { decodeExtension, extensionEncoder } from "./extension.js";
import { decodeKeyPackage, keyPackageEncoder } from "./keyPackage.js";
import { decodePskId, pskIdEncoder } from "./presharedkey.js";
import { decodeDefaultProposalType, defaultProposalTypeEncoder } from "./defaultProposalType.js";
import { decodeProtocolVersion, protocolVersionEncoder } from "./protocolVersion.js";
import { decodeLeafNodeUpdate, leafNodeEncoder } from "./leafNode.js";
export const addEncoder = contramapBufferEncoder(keyPackageEncoder, (a) => a.keyPackage);
export const encodeAdd = encode(addEncoder);
export const decodeAdd = mapDecoder(decodeKeyPackage, (keyPackage) => ({ keyPackage }));
export const updateEncoder = contramapBufferEncoder(leafNodeEncoder, (u) => u.leafNode);
export const encodeUpdate = encode(updateEncoder);
export const decodeUpdate = mapDecoder(decodeLeafNodeUpdate, (leafNode) => ({ leafNode }));
export const removeEncoder = contramapBufferEncoder(uint32Encoder, (r) => r.removed);
export const encodeRemove = encode(removeEncoder);
export const decodeRemove = mapDecoder(decodeUint32, (removed) => ({ removed }));
export const pskEncoder = contramapBufferEncoder(pskIdEncoder, (p) => p.preSharedKeyId);
export const encodePSK = encode(pskEncoder);
export const decodePSK = mapDecoder(decodePskId, (preSharedKeyId) => ({ preSharedKeyId }));
export const reinitEncoder = contramapBufferEncoders([varLenDataEncoder, protocolVersionEncoder, ciphersuiteEncoder, varLenTypeEncoder(extensionEncoder)], (r) => [r.groupId, r.version, r.cipherSuite, r.extensions]);
export const encodeReinit = encode(reinitEncoder);
export const decodeReinit = mapDecoders([decodeVarLenData, decodeProtocolVersion, decodeCiphersuite, decodeVarLenType(decodeExtension)], (groupId, version, cipherSuite, extensions) => ({ groupId, version, cipherSuite, extensions }));
export const externalInitEncoder = contramapBufferEncoder(varLenDataEncoder, (e) => e.kemOutput);
export const encodeExternalInit = encode(externalInitEncoder);
export const decodeExternalInit = mapDecoder(decodeVarLenData, (kemOutput) => ({ kemOutput }));
export const groupContextExtensionsEncoder = contramapBufferEncoder(varLenTypeEncoder(extensionEncoder), (g) => g.extensions);
export const encodeGroupContextExtensions = encode(groupContextExtensionsEncoder);
export const decodeGroupContextExtensions = mapDecoder(decodeVarLenType(decodeExtension), (extensions) => ({ extensions }));
export const proposalAddEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, addEncoder], (p) => [p.proposalType, p.add]);
export const encodeProposalAdd = encode(proposalAddEncoder);
export const proposalUpdateEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, updateEncoder], (p) => [p.proposalType, p.update]);
export const encodeProposalUpdate = encode(proposalUpdateEncoder);
export const proposalRemoveEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, removeEncoder], (p) => [p.proposalType, p.remove]);
export const encodeProposalRemove = encode(proposalRemoveEncoder);
export const proposalPSKEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, pskEncoder], (p) => [p.proposalType, p.psk]);
export const encodeProposalPSK = encode(proposalPSKEncoder);
export const proposalReinitEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, reinitEncoder], (p) => [p.proposalType, p.reinit]);
export const encodeProposalReinit = encode(proposalReinitEncoder);
export const proposalExternalInitEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, externalInitEncoder], (p) => [p.proposalType, p.externalInit]);
export const encodeProposalExternalInit = encode(proposalExternalInitEncoder);
export const proposalGroupContextExtensionsEncoder = contramapBufferEncoders([defaultProposalTypeEncoder, groupContextExtensionsEncoder], (p) => [p.proposalType, p.groupContextExtensions]);
export const encodeProposalGroupContextExtensions = encode(proposalGroupContextExtensionsEncoder);
export const proposalCustomEncoder = contramapBufferEncoders([uint16Encoder, varLenDataEncoder], (p) => [p.proposalType, p.proposalData]);
export const encodeProposalCustom = encode(proposalCustomEncoder);
export const proposalEncoder = (p) => {
    switch (p.proposalType) {
        case "add":
            return proposalAddEncoder(p);
        case "update":
            return proposalUpdateEncoder(p);
        case "remove":
            return proposalRemoveEncoder(p);
        case "psk":
            return proposalPSKEncoder(p);
        case "reinit":
            return proposalReinitEncoder(p);
        case "external_init":
            return proposalExternalInitEncoder(p);
        case "group_context_extensions":
            return proposalGroupContextExtensionsEncoder(p);
        default:
            return proposalCustomEncoder(p);
    }
};
export const encodeProposal = encode(proposalEncoder);
export const decodeProposalAdd = mapDecoder(decodeAdd, (add) => ({ proposalType: "add", add }));
export const decodeProposalUpdate = mapDecoder(decodeUpdate, (update) => ({
    proposalType: "update",
    update,
}));
export const decodeProposalRemove = mapDecoder(decodeRemove, (remove) => ({
    proposalType: "remove",
    remove,
}));
export const decodeProposalPSK = mapDecoder(decodePSK, (psk) => ({ proposalType: "psk", psk }));
export const decodeProposalReinit = mapDecoder(decodeReinit, (reinit) => ({
    proposalType: "reinit",
    reinit,
}));
export const decodeProposalExternalInit = mapDecoder(decodeExternalInit, (externalInit) => ({ proposalType: "external_init", externalInit }));
export const decodeProposalGroupContextExtensions = mapDecoder(decodeGroupContextExtensions, (groupContextExtensions) => ({ proposalType: "group_context_extensions", groupContextExtensions }));
export function decodeProposalCustom(proposalType) {
    return mapDecoder(decodeVarLenData, (proposalData) => ({ proposalType, proposalData }));
}
export const decodeProposal = orDecoder(flatMapDecoder(decodeDefaultProposalType, (proposalType) => {
    switch (proposalType) {
        case "add":
            return decodeProposalAdd;
        case "update":
            return decodeProposalUpdate;
        case "remove":
            return decodeProposalRemove;
        case "psk":
            return decodeProposalPSK;
        case "reinit":
            return decodeProposalReinit;
        case "external_init":
            return decodeProposalExternalInit;
        case "group_context_extensions":
            return decodeProposalGroupContextExtensions;
    }
}), flatMapDecoder(decodeUint16, (n) => decodeProposalCustom(n)));
//# sourceMappingURL=proposal.js.map