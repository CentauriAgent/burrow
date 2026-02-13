import { Capabilities } from "./capabilities.js";
import { CredentialTypeName } from "./credentialType.js";
import { CiphersuiteName } from "./crypto/ciphersuite.js";
import { Extension } from "./extension.js";
export declare const greaseValues: number[];
export interface GreaseConfig {
    probabilityPerGreaseValue: number;
}
export declare const defaultGreaseConfig: {
    probabilityPerGreaseValue: number;
};
export declare function grease(greaseConfig: GreaseConfig): number[];
export declare function greaseCiphersuites(greaseConfig: GreaseConfig): CiphersuiteName[];
export declare function greaseCredentials(greaseConfig: GreaseConfig): CredentialTypeName[];
export declare function greaseExtensions(greaseConfig: GreaseConfig): Extension[];
export declare function greaseCapabilities(config: GreaseConfig, capabilities: Capabilities): Capabilities;
