import { ClientState } from "./clientState.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { MLSMessage } from "./message.js";
import { PrivateMessage } from "./privateMessage.js";
import { Proposal } from "./proposal.js";
/** @public */
export declare function createProposal(state: ClientState, publicMessage: boolean, proposal: Proposal, cs: CiphersuiteImpl, authenticatedData?: Uint8Array): Promise<{
    newState: ClientState;
    message: MLSMessage;
    consumed: Uint8Array[];
}>;
/** @public */
export declare function createApplicationMessage(state: ClientState, message: Uint8Array, cs: CiphersuiteImpl, authenticatedData?: Uint8Array): Promise<{
    newState: ClientState;
    privateMessage: PrivateMessage;
    consumed: Uint8Array[];
}>;
