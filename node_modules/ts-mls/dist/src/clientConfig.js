import { defaultAuthenticationService } from "./authenticationService.js";
import { defaultKeyPackageEqualityConfig } from "./keyPackageEqualityConfig.js";
import { defaultKeyRetentionConfig } from "./keyRetentionConfig.js";
import { defaultLifetimeConfig } from "./lifetimeConfig.js";
import { defaultPaddingConfig } from "./paddingConfig.js";
export const defaultClientConfig = {
    keyRetentionConfig: defaultKeyRetentionConfig,
    lifetimeConfig: defaultLifetimeConfig,
    keyPackageEqualityConfig: defaultKeyPackageEqualityConfig,
    paddingConfig: defaultPaddingConfig,
    authService: defaultAuthenticationService,
};
//# sourceMappingURL=clientConfig.js.map