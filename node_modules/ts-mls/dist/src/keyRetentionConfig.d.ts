/** @public */
export interface KeyRetentionConfig {
    retainKeysForGenerations: number;
    retainKeysForEpochs: number;
    maximumForwardRatchetSteps: number;
}
/** @public */
export declare const defaultKeyRetentionConfig: KeyRetentionConfig;
