export function enumNumberToKey(t) {
    return (n) => (Object.values(t).includes(n) ? reverseMap(t)[n] : undefined);
}
export function reverseMap(obj) {
    return Object.entries(obj).reduce((acc, [key, value]) => ({
        ...acc,
        [value]: key,
    }), {});
}
export function openEnumNumberToKey(rec) {
    return (n) => {
        const decoded = enumNumberToKey(rec)(n);
        if (decoded === undefined)
            return n.toString();
        else
            return decoded;
    };
}
export function openEnumNumberEncoder(rec) {
    return (s) => {
        const x = rec[s];
        if (x === undefined)
            return Number(s);
        else
            return x;
    };
}
//# sourceMappingURL=enumHelpers.js.map