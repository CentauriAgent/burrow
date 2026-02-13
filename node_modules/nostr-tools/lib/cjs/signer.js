"use strict";
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// signer.ts
var signer_exports = {};
__export(signer_exports, {
  PlainKeySigner: () => PlainKeySigner
});
module.exports = __toCommonJS(signer_exports);

// pure.ts
var import_secp256k1 = require("@noble/curves/secp256k1.js");
var import_utils2 = require("@noble/hashes/utils.js");

// core.ts
var verifiedSymbol = Symbol("verified");
var isRecord = (obj) => obj instanceof Object;
function validateEvent(event) {
  if (!isRecord(event))
    return false;
  if (typeof event.kind !== "number")
    return false;
  if (typeof event.content !== "string")
    return false;
  if (typeof event.created_at !== "number")
    return false;
  if (typeof event.pubkey !== "string")
    return false;
  if (!event.pubkey.match(/^[a-f0-9]{64}$/))
    return false;
  if (!Array.isArray(event.tags))
    return false;
  for (let i2 = 0; i2 < event.tags.length; i2++) {
    let tag = event.tags[i2];
    if (!Array.isArray(tag))
      return false;
    for (let j = 0; j < tag.length; j++) {
      if (typeof tag[j] !== "string")
        return false;
    }
  }
  return true;
}

// pure.ts
var import_sha2 = require("@noble/hashes/sha2.js");

// utils.ts
var import_utils = require("@noble/hashes/utils.js");
var utf8Decoder = new TextDecoder("utf-8");
var utf8Encoder = new TextEncoder();

// pure.ts
var JS = class {
  generateSecretKey() {
    return import_secp256k1.schnorr.utils.randomSecretKey();
  }
  getPublicKey(secretKey) {
    return (0, import_utils2.bytesToHex)(import_secp256k1.schnorr.getPublicKey(secretKey));
  }
  finalizeEvent(t, secretKey) {
    const event = t;
    event.pubkey = (0, import_utils2.bytesToHex)(import_secp256k1.schnorr.getPublicKey(secretKey));
    event.id = getEventHash(event);
    event.sig = (0, import_utils2.bytesToHex)(import_secp256k1.schnorr.sign((0, import_utils2.hexToBytes)(getEventHash(event)), secretKey));
    event[verifiedSymbol] = true;
    return event;
  }
  verifyEvent(event) {
    if (typeof event[verifiedSymbol] === "boolean")
      return event[verifiedSymbol];
    const hash = getEventHash(event);
    if (hash !== event.id) {
      event[verifiedSymbol] = false;
      return false;
    }
    try {
      const valid = import_secp256k1.schnorr.verify((0, import_utils2.hexToBytes)(event.sig), (0, import_utils2.hexToBytes)(hash), (0, import_utils2.hexToBytes)(event.pubkey));
      event[verifiedSymbol] = valid;
      return valid;
    } catch (err) {
      event[verifiedSymbol] = false;
      return false;
    }
  }
};
function serializeEvent(evt) {
  if (!validateEvent(evt))
    throw new Error("can't serialize event with wrong or missing properties");
  return JSON.stringify([0, evt.pubkey, evt.created_at, evt.kind, evt.tags, evt.content]);
}
function getEventHash(event) {
  let eventHash = (0, import_sha2.sha256)(utf8Encoder.encode(serializeEvent(event)));
  return (0, import_utils2.bytesToHex)(eventHash);
}
var i = new JS();
var generateSecretKey = i.generateSecretKey;
var getPublicKey = i.getPublicKey;
var finalizeEvent = i.finalizeEvent;
var verifyEvent = i.verifyEvent;

// signer.ts
var PlainKeySigner = class {
  secretKey;
  constructor(secretKey) {
    this.secretKey = secretKey;
  }
  async getPublicKey() {
    return getPublicKey(this.secretKey);
  }
  async signEvent(event) {
    return finalizeEvent(event, this.secretKey);
  }
};
