import { ClientConfig } from "../clientConfig.js";
import { ClientState } from "../clientState.js";
/**
 * @deprecated Use encodeGroupState instead for binary serialization
 */
export declare function toJsonString(clientState: ClientState): string;
/**
 * @deprecated Use decodeGroupState instead for binary deserialization
 */
export declare function fromJsonString(s: string, config: ClientConfig): ClientState | undefined;
