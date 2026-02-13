/** @public */
export interface LifetimeConfig {
    maximumTotalLifetime: bigint;
    validateLifetimeOnReceive: boolean;
}
/** @public */
export declare const defaultLifetimeConfig: LifetimeConfig;
