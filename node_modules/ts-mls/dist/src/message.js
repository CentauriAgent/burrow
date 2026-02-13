import { flatMapDecoder, mapDecoder, mapDecoders } from "./codec/tlsDecoder.js";
import { contramapBufferEncoders, encode } from "./codec/tlsEncoder.js";
import { decodeGroupInfo, groupInfoEncoder } from "./groupInfo.js";
import { decodeKeyPackage, keyPackageEncoder } from "./keyPackage.js";
import { decodePrivateMessage, privateMessageEncoder } from "./privateMessage.js";
import { decodeProtocolVersion, protocolVersionEncoder } from "./protocolVersion.js";
import { decodePublicMessage, publicMessageEncoder } from "./publicMessage.js";
import { decodeWelcome, welcomeEncoder } from "./welcome.js";
import { decodeWireformat, wireformatEncoder } from "./wireformat.js";
export const mlsPublicMessageEncoder = contramapBufferEncoders([wireformatEncoder, publicMessageEncoder], (msg) => [msg.wireformat, msg.publicMessage]);
export const encodeMlsPublicMessage = encode(mlsPublicMessageEncoder);
export const mlsWelcomeEncoder = contramapBufferEncoders([wireformatEncoder, welcomeEncoder], (wm) => [wm.wireformat, wm.welcome]);
export const encodeMlsWelcome = encode(mlsWelcomeEncoder);
export const mlsPrivateMessageEncoder = contramapBufferEncoders([wireformatEncoder, privateMessageEncoder], (pm) => [pm.wireformat, pm.privateMessage]);
export const encodeMlsPrivateMessage = encode(mlsPrivateMessageEncoder);
export const mlsGroupInfoEncoder = contramapBufferEncoders([wireformatEncoder, groupInfoEncoder], (gi) => [gi.wireformat, gi.groupInfo]);
export const encodeMlsGroupInfo = encode(mlsGroupInfoEncoder);
export const mlsKeyPackageEncoder = contramapBufferEncoders([wireformatEncoder, keyPackageEncoder], (kp) => [kp.wireformat, kp.keyPackage]);
export const encodeMlsKeyPackage = encode(mlsKeyPackageEncoder);
export const mlsMessageContentEncoder = (mc) => {
    switch (mc.wireformat) {
        case "mls_public_message":
            return mlsPublicMessageEncoder(mc);
        case "mls_welcome":
            return mlsWelcomeEncoder(mc);
        case "mls_private_message":
            return mlsPrivateMessageEncoder(mc);
        case "mls_group_info":
            return mlsGroupInfoEncoder(mc);
        case "mls_key_package":
            return mlsKeyPackageEncoder(mc);
    }
};
export const encodeMlsMessageContent = encode(mlsMessageContentEncoder);
export const decodeMlsMessageContent = flatMapDecoder(decodeWireformat, (wireformat) => {
    switch (wireformat) {
        case "mls_public_message":
            return mapDecoder(decodePublicMessage, (publicMessage) => ({ wireformat, publicMessage }));
        case "mls_welcome":
            return mapDecoder(decodeWelcome, (welcome) => ({ wireformat, welcome }));
        case "mls_private_message":
            return mapDecoder(decodePrivateMessage, (privateMessage) => ({ wireformat, privateMessage }));
        case "mls_group_info":
            return mapDecoder(decodeGroupInfo, (groupInfo) => ({ wireformat, groupInfo }));
        case "mls_key_package":
            return mapDecoder(decodeKeyPackage, (keyPackage) => ({ wireformat, keyPackage }));
    }
});
export const mlsMessageEncoder = contramapBufferEncoders([protocolVersionEncoder, mlsMessageContentEncoder], (w) => [w.version, w]);
/** @public */
export const encodeMlsMessage = encode(mlsMessageEncoder);
/** @public */
export const decodeMlsMessage = mapDecoders([decodeProtocolVersion, decodeMlsMessageContent], (version, mc) => ({ ...mc, version }));
//# sourceMappingURL=message.js.map