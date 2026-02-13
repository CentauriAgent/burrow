import { Decoder } from "./codec/tlsDecoder.js";
import { BufferEncoder, Encoder } from "./codec/tlsEncoder.js";
import { GroupInfo } from "./groupInfo.js";
import { KeyPackage } from "./keyPackage.js";
import { PrivateMessage } from "./privateMessage.js";
import { ProtocolVersionName } from "./protocolVersion.js";
import { PublicMessage } from "./publicMessage.js";
import { Welcome } from "./welcome.js";
/** @public */
export interface MlsMessageProtocol {
    version: ProtocolVersionName;
}
/** @public */
export interface MlsWelcome {
    wireformat: "mls_welcome";
    welcome: Welcome;
}
/** @public */
export interface MlsPrivateMessage {
    wireformat: "mls_private_message";
    privateMessage: PrivateMessage;
}
/** @public */
export interface MlsGroupInfo {
    wireformat: "mls_group_info";
    groupInfo: GroupInfo;
}
/** @public */
export interface MlsKeyPackage {
    wireformat: "mls_key_package";
    keyPackage: KeyPackage;
}
/** @public */
export interface MlsPublicMessage {
    wireformat: "mls_public_message";
    publicMessage: PublicMessage;
}
/** @public */
export type MlsMessageContent = MlsWelcome | MlsPrivateMessage | MlsGroupInfo | MlsKeyPackage | MlsPublicMessage;
/** @public */
export type MLSMessage = MlsMessageProtocol & MlsMessageContent;
export declare const mlsPublicMessageEncoder: BufferEncoder<MlsPublicMessage>;
export declare const encodeMlsPublicMessage: Encoder<MlsPublicMessage>;
export declare const mlsWelcomeEncoder: BufferEncoder<MlsWelcome>;
export declare const encodeMlsWelcome: Encoder<MlsWelcome>;
export declare const mlsPrivateMessageEncoder: BufferEncoder<MlsPrivateMessage>;
export declare const encodeMlsPrivateMessage: Encoder<MlsPrivateMessage>;
export declare const mlsGroupInfoEncoder: BufferEncoder<MlsGroupInfo>;
export declare const encodeMlsGroupInfo: Encoder<MlsGroupInfo>;
export declare const mlsKeyPackageEncoder: BufferEncoder<MlsKeyPackage>;
export declare const encodeMlsKeyPackage: Encoder<MlsKeyPackage>;
export declare const mlsMessageContentEncoder: BufferEncoder<MlsMessageContent>;
export declare const encodeMlsMessageContent: Encoder<MlsMessageContent>;
export declare const decodeMlsMessageContent: Decoder<MlsMessageContent>;
export declare const mlsMessageEncoder: BufferEncoder<MLSMessage>;
/** @public */
export declare const encodeMlsMessage: Encoder<MLSMessage>;
/** @public */
export declare const decodeMlsMessage: Decoder<MLSMessage>;
