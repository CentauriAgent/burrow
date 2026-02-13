import { ValidationError } from "./mlsError.js";
import { updatePskSecret } from "./presharedkey.js";
/** @public */
export const emptyPskIndex = {
    findPsk(_preSharedKeyId) {
        return undefined;
    },
};
export async function accumulatePskSecret(groupedPsk, pskSearch, cs, zeroes) {
    return groupedPsk.reduce(async (acc, cur, index) => {
        const [previousSecret, ids] = await acc;
        const psk = pskSearch.findPsk(cur);
        if (psk === undefined)
            throw new ValidationError("Could not find pskId referenced in proposal");
        const pskSecret = await updatePskSecret(previousSecret, cur, psk, index, groupedPsk.length, cs);
        return [pskSecret, [...ids, cur]];
    }, Promise.resolve([zeroes, []]));
}
//# sourceMappingURL=pskIndex.js.map