/**
 * @deprecated Use encodeGroupState instead for binary serialization
 */
export function toJsonString(clientState) {
    const { clientConfig, ...state } = clientState;
    const stateWithSerializableMap = {
        ...state,
        historicalReceiverData: Array.from(state.historicalReceiverData.entries()).map(([epoch, data]) => [
            {
                epoch: epoch.toString(),
            },
            data,
        ]),
    };
    return JSON.stringify(stateWithSerializableMap, (_key, value) => {
        // Mark BigInt values with a special wrapper
        if (typeof value === "bigint") {
            return { "@@bigint": value.toString() };
        }
        // Mark empty Uint8Arrays with a special marker
        if (value instanceof Uint8Array) {
            if (value.length === 0) {
                return { "@@uint8array": true, length: 0, data: [] };
            }
        }
        return value;
    });
}
function isValidGroupActiveState(state) {
    if (typeof state !== "object" || state === null)
        return false;
    const s = state;
    if (typeof s.kind !== "string")
        return false;
    if (s.kind === "active")
        return true;
    if (s.kind === "suspendedPendingReinit")
        return "reinit" in s && typeof s.reinit === "object";
    if (s.kind === "removedFromGroup")
        return true;
    return false;
}
function isValidRatchetTree(tree) {
    if (!Array.isArray(tree))
        return false;
    return tree.every((node) => node === null || (typeof node === "object" && node !== null));
}
function isValidGroupContext(ctx) {
    if (typeof ctx !== "object" || ctx === null)
        return false;
    const c = ctx;
    return ("version" in c &&
        "cipherSuite" in c &&
        "groupId" in c &&
        "epoch" in c &&
        "treeHash" in c &&
        "confirmedTranscriptHash" in c &&
        "extensions" in c);
}
function isValidKeySchedule(ks) {
    if (typeof ks !== "object" || ks === null)
        return false;
    const k = ks;
    return "epochAuthenticator" in k && typeof k.epochAuthenticator === "object";
}
function isValidPrivateKeyPath(pkp) {
    if (typeof pkp !== "object" || pkp === null)
        return false;
    const p = pkp;
    return "leafIndex" in p && typeof p.leafIndex === "number";
}
function isValidUnappliedProposals(uap) {
    return uap !== null && typeof uap === "object";
}
function isValidHistoricalReceiverData(hrd) {
    if (!Array.isArray(hrd))
        return false;
    return hrd.every((item) => Array.isArray(item) && item.length === 2 && typeof item[0] === "object" && "epoch" in item[0]);
}
function deepConvertUint8Arrays(obj, depth = 0, maxDepth = 20) {
    if (depth > maxDepth)
        return obj;
    if (obj === null || obj === undefined)
        return obj;
    if (obj instanceof Uint8Array)
        return obj;
    // Check for the special BigInt marker
    if (obj && typeof obj === "object" && "@@bigint" in obj) {
        const objRecord = obj;
        if (typeof objRecord["@@bigint"] === "string") {
            return BigInt(objRecord["@@bigint"]);
        }
    }
    // Check for the special empty Uint8Array marker
    if (obj && typeof obj === "object" && "@@uint8array" in obj) {
        const objRecord = obj;
        if (objRecord["@@uint8array"] === true) {
            return new Uint8Array();
        }
    }
    // Handle non-empty Uint8Array-like objects
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
        const objRecord = obj;
        const keys = Object.keys(objRecord);
        if (keys.length > 0 && !("@@uint8array" in objRecord) && !("@@bigint" in objRecord)) {
            // Check if all keys are numeric strings and all values are 0-255 numbers
            const allNumericKeys = keys.every((k) => /^\d+$/.test(k));
            if (allNumericKeys) {
                const allValidValues = keys.every((k) => Object.prototype.hasOwnProperty.call(objRecord, k) &&
                    typeof objRecord[k] === "number" &&
                    objRecord[k] >= 0 &&
                    objRecord[k] <= 255);
                if (allValidValues) {
                    const numKeys = keys.map((k) => parseInt(k, 10));
                    const values = numKeys.sort((a, b) => a - b).map((n) => objRecord[String(n)]);
                    return new Uint8Array(values);
                }
            }
        }
    }
    if (Array.isArray(obj)) {
        return obj.map((item) => deepConvertUint8Arrays(item, depth + 1, maxDepth));
    }
    if (typeof obj === "object") {
        const objRecord = obj;
        const result = {};
        for (const key in objRecord) {
            if (Object.prototype.hasOwnProperty.call(objRecord, key)) {
                result[key] = deepConvertUint8Arrays(objRecord[key], depth + 1, maxDepth);
            }
        }
        return result;
    }
    return obj;
}
/**
 * @deprecated Use decodeGroupState instead for binary deserialization
 */
export function fromJsonString(s, config) {
    try {
        const parsed = JSON.parse(s);
        if (typeof parsed !== "object" || parsed === null)
            return undefined;
        const parsedRecord = parsed;
        if (!("groupActiveState" in parsedRecord) ||
            !("privatePath" in parsedRecord) ||
            !("ratchetTree" in parsedRecord) ||
            !("keySchedule" in parsedRecord) ||
            !("groupContext" in parsedRecord) ||
            !("unappliedProposals" in parsedRecord) ||
            !("signaturePrivateKey" in parsedRecord) ||
            !("confirmationTag" in parsedRecord) ||
            !("historicalReceiverData" in parsedRecord) ||
            !("secretTree" in parsedRecord)) {
            return undefined;
        }
        const converted = deepConvertUint8Arrays(parsedRecord);
        if (!isValidGroupActiveState(converted.groupActiveState))
            return undefined;
        if (!isValidPrivateKeyPath(converted.privatePath))
            return undefined;
        if (!isValidRatchetTree(converted.ratchetTree))
            return undefined;
        if (!isValidKeySchedule(converted.keySchedule))
            return undefined;
        if (!isValidGroupContext(converted.groupContext))
            return undefined;
        if (!isValidUnappliedProposals(converted.unappliedProposals))
            return undefined;
        if (!isValidHistoricalReceiverData(converted.historicalReceiverData))
            return undefined;
        if (!(converted.signaturePrivateKey instanceof Uint8Array || typeof converted.signaturePrivateKey === "object")) {
            return undefined;
        }
        if (!(converted.confirmationTag instanceof Uint8Array || typeof converted.confirmationTag === "object")) {
            return undefined;
        }
        // Reconstruct Map<bigint, EpochReceiverData>
        const historicalReceiverData = new Map();
        if (Array.isArray(converted.historicalReceiverData)) {
            for (const [keyObj, data] of converted.historicalReceiverData) {
                if (keyObj && typeof keyObj === "object" && "epoch" in keyObj) {
                    const keyObjRecord = keyObj;
                    if (typeof keyObjRecord.epoch === "bigint") {
                        historicalReceiverData.set(keyObjRecord.epoch, data);
                    }
                }
            }
        }
        return { clientConfig: config, ...converted, historicalReceiverData };
    }
    catch {
        return undefined;
    }
}
//# sourceMappingURL=json.js.map