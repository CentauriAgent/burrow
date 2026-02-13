import { ProposalWithSender } from "./unappliedProposals.js";
import type { LeafIndex } from "./treemath.js";
/** @public */
export type IncomingMessageAction = "accept" | "reject";
/** @public */
export type IncomingMessageCallback = (incoming: {
    kind: "commit";
    senderLeafIndex: LeafIndex | undefined;
    proposals: ProposalWithSender[];
} | {
    kind: "proposal";
    proposal: ProposalWithSender;
}) => IncomingMessageAction;
/** @public */
export declare const acceptAll: IncomingMessageCallback;
