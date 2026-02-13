import { ClientState } from "./clientState.js";
import { CiphersuiteImpl } from "./crypto/ciphersuite.js";
import { IncomingMessageAction, IncomingMessageCallback } from "./incomingMessageAction.js";
import { MlsPrivateMessage, MlsPublicMessage } from "./message.js";
import { PrivateMessage } from "./privateMessage.js";
import { PskIndex } from "./pskIndex.js";
import { PublicMessage } from "./publicMessage.js";
/** @public */
export type ProcessMessageResult = {
    kind: "newState";
    newState: ClientState;
    actionTaken: IncomingMessageAction;
    consumed: Uint8Array[];
} | {
    kind: "applicationMessage";
    message: Uint8Array;
    newState: ClientState;
    consumed: Uint8Array[];
};
/**
 * Process private message and apply proposal or commit and return the updated ClientState or return an application message
 *
 * @public
 */
export declare function processPrivateMessage(state: ClientState, pm: PrivateMessage, pskSearch: PskIndex, cs: CiphersuiteImpl, callback?: IncomingMessageCallback): Promise<ProcessMessageResult>;
/** @public */
export interface NewStateWithActionTaken {
    newState: ClientState;
    actionTaken: IncomingMessageAction;
    consumed: Uint8Array[];
}
/** @public */
export declare function processPublicMessage(state: ClientState, pm: PublicMessage, pskSearch: PskIndex, cs: CiphersuiteImpl, callback?: IncomingMessageCallback): Promise<NewStateWithActionTaken>;
/** @public */
export declare function processMessage(message: MlsPrivateMessage | MlsPublicMessage, state: ClientState, pskIndex: PskIndex, action: IncomingMessageCallback, cs: CiphersuiteImpl): Promise<ProcessMessageResult>;
