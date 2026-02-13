import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { CiphersuiteName } from "./crypto/ciphersuite.js";
import { Extension } from "./extension.js";
import { KeyPackage } from "./keyPackage.js";
import { PreSharedKeyID } from "./presharedkey.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { LeafNodeUpdate } from "./leafNode.js";
/** @public */
export interface Add {
    keyPackage: KeyPackage;
}
export declare const addEncoder: BufferEncoder<Add>;
export declare const encodeAdd: Encoder<Add>;
export declare const decodeAdd: Decoder<Add>;
/** @public */
export interface Update {
    leafNode: LeafNodeUpdate;
}
export declare const updateEncoder: BufferEncoder<Update>;
export declare const encodeUpdate: Encoder<Update>;
export declare const decodeUpdate: Decoder<Update>;
/** @public */
export interface Remove {
    removed: number;
}
export declare const removeEncoder: BufferEncoder<Remove>;
export declare const encodeRemove: Encoder<Remove>;
export declare const decodeRemove: Decoder<Remove>;
/** @public */
export interface PSK {
    preSharedKeyId: PreSharedKeyID;
}
export declare const pskEncoder: BufferEncoder<PSK>;
export declare const encodePSK: Encoder<PSK>;
export declare const decodePSK: Decoder<PSK>;
/** @public */
export interface Reinit {
    groupId: Uint8Array;
    version: ProtocolVersionName;
    cipherSuite: CiphersuiteName;
    extensions: Extension[];
}
export declare const reinitEncoder: BufferEncoder<Reinit>;
export declare const encodeReinit: Encoder<Reinit>;
export declare const decodeReinit: Decoder<Reinit>;
/** @public */
export interface ExternalInit {
    kemOutput: Uint8Array;
}
export declare const externalInitEncoder: BufferEncoder<ExternalInit>;
export declare const encodeExternalInit: Encoder<ExternalInit>;
export declare const decodeExternalInit: Decoder<ExternalInit>;
/** @public */
export interface GroupContextExtensions {
    extensions: Extension[];
}
export declare const groupContextExtensionsEncoder: BufferEncoder<GroupContextExtensions>;
export declare const encodeGroupContextExtensions: Encoder<GroupContextExtensions>;
export declare const decodeGroupContextExtensions: Decoder<GroupContextExtensions>;
/** @public */
export interface ProposalAdd {
    proposalType: "add";
    add: Add;
}
/** @public */
export interface ProposalUpdate {
    proposalType: "update";
    update: Update;
}
/** @public */
export interface ProposalRemove {
    proposalType: "remove";
    remove: Remove;
}
/** @public */
export interface ProposalPSK {
    proposalType: "psk";
    psk: PSK;
}
/** @public */
export interface ProposalReinit {
    proposalType: "reinit";
    reinit: Reinit;
}
/** @public */
export interface ProposalExternalInit {
    proposalType: "external_init";
    externalInit: ExternalInit;
}
/** @public */
export interface ProposalGroupContextExtensions {
    proposalType: "group_context_extensions";
    groupContextExtensions: GroupContextExtensions;
}
/** @public */
export interface ProposalCustom {
    proposalType: number;
    proposalData: Uint8Array;
}
/** @public */
export type Proposal = ProposalAdd | ProposalUpdate | ProposalRemove | ProposalPSK | ProposalReinit | ProposalExternalInit | ProposalGroupContextExtensions | ProposalCustom;
export declare const proposalAddEncoder: BufferEncoder<ProposalAdd>;
export declare const encodeProposalAdd: Encoder<ProposalAdd>;
export declare const proposalUpdateEncoder: BufferEncoder<ProposalUpdate>;
export declare const encodeProposalUpdate: Encoder<ProposalUpdate>;
export declare const proposalRemoveEncoder: BufferEncoder<ProposalRemove>;
export declare const encodeProposalRemove: Encoder<ProposalRemove>;
export declare const proposalPSKEncoder: BufferEncoder<ProposalPSK>;
export declare const encodeProposalPSK: Encoder<ProposalPSK>;
export declare const proposalReinitEncoder: BufferEncoder<ProposalReinit>;
export declare const encodeProposalReinit: Encoder<ProposalReinit>;
export declare const proposalExternalInitEncoder: BufferEncoder<ProposalExternalInit>;
export declare const encodeProposalExternalInit: Encoder<ProposalExternalInit>;
export declare const proposalGroupContextExtensionsEncoder: BufferEncoder<ProposalGroupContextExtensions>;
export declare const encodeProposalGroupContextExtensions: Encoder<ProposalGroupContextExtensions>;
export declare const proposalCustomEncoder: BufferEncoder<ProposalCustom>;
export declare const encodeProposalCustom: Encoder<ProposalCustom>;
export declare const proposalEncoder: BufferEncoder<Proposal>;
export declare const encodeProposal: Encoder<Proposal>;
export declare const decodeProposalAdd: Decoder<ProposalAdd>;
export declare const decodeProposalUpdate: Decoder<ProposalUpdate>;
export declare const decodeProposalRemove: Decoder<ProposalRemove>;
export declare const decodeProposalPSK: Decoder<ProposalPSK>;
export declare const decodeProposalReinit: Decoder<ProposalReinit>;
export declare const decodeProposalExternalInit: Decoder<ProposalExternalInit>;
export declare const decodeProposalGroupContextExtensions: Decoder<ProposalGroupContextExtensions>;
export declare function decodeProposalCustom(proposalType: number): Decoder<ProposalCustom>;
export declare const decodeProposal: Decoder<Proposal>;
