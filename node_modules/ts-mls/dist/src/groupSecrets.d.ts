import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { PreSharedKeyID } from "./presharedkey.js";
export interface GroupSecrets {
    joinerSecret: Uint8Array;
    pathSecret: Uint8Array | undefined;
    psks: PreSharedKeyID[];
}
export declare const groupSecretsEncoder: BufferEncoder<GroupSecrets>;
export declare const encodeGroupSecrets: Encoder<GroupSecrets>;
export declare const decodeGroupSecrets: Decoder<GroupSecrets>;
