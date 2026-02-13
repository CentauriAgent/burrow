/**
 * Burrow type definitions — Marmot Protocol types for Nostr + MLS
 */
// Nostr event kinds for Marmot protocol
export const MARMOT_KINDS = {
    KEY_PACKAGE: 443,
    WELCOME: 444,
    GROUP_MESSAGE: 445,
    KEY_PACKAGE_RELAY_LIST: 10051,
};
// Marmot Group Data Extension ID
export const MARMOT_EXTENSION_ID = 0xf2ee;
export const LAST_RESORT_EXTENSION_ID = 0x000a;
export const DEFAULT_RELAYS = [
    'wss://relay.ditto.pub',
    'wss://relay.primal.net',
    'wss://nos.lol',
];
export const DEFAULT_CIPHERSUITE = 'MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519';
//# sourceMappingURL=index.js.map