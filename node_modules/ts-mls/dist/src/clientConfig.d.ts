import { AuthenticationService } from "./authenticationService.js";
import { KeyPackageEqualityConfig } from "./keyPackageEqualityConfig.js";
import { KeyRetentionConfig } from "./keyRetentionConfig.js";
import { LifetimeConfig } from "./lifetimeConfig.js";
import { PaddingConfig } from "./paddingConfig.js";
/** @public */
export interface ClientConfig {
    keyRetentionConfig: KeyRetentionConfig;
    lifetimeConfig: LifetimeConfig;
    keyPackageEqualityConfig: KeyPackageEqualityConfig;
    paddingConfig: PaddingConfig;
    authService: AuthenticationService;
}
export declare const defaultClientConfig: {
    keyRetentionConfig: KeyRetentionConfig;
    lifetimeConfig: LifetimeConfig;
    keyPackageEqualityConfig: KeyPackageEqualityConfig;
    paddingConfig: PaddingConfig;
    authService: {
        validateCredential(_credential: import("./credential.js").Credential, _signaturePublicKey: Uint8Array): Promise<boolean>;
    };
};
