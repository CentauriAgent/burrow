var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var _Mutex_locked;
export class Mutex {
    constructor() {
        _Mutex_locked.set(this, Promise.resolve());
    }
    async lock() {
        let releaseLock;
        const nextLock = new Promise((resolve) => {
            releaseLock = resolve;
        });
        const previousLock = __classPrivateFieldGet(this, _Mutex_locked, "f");
        __classPrivateFieldSet(this, _Mutex_locked, nextLock, "f");
        await previousLock;
        return releaseLock;
    }
}
_Mutex_locked = new WeakMap();
