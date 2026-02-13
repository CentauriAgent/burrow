export function arraysEqual(a, b) {
    if (a.length !== b.length)
        return false;
    return a.every((val, index) => val === b[index]);
}
//# sourceMappingURL=array.js.map