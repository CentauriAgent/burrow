(function (factory) {
    if (typeof module === "object" && typeof module.exports === "object") {
        var v = factory(require, exports);
        if (v !== undefined) module.exports = v;
    }
    else if (typeof define === "function" && define.amd) {
        define(["require", "exports", "@hpke/common"], factory);
    }
})(function (require, exports) {
    "use strict";
    Object.defineProperty(exports, "__esModule", { value: true });
    exports.emitNotSupported = emitNotSupported;
    const common_1 = require("@hpke/common");
    function emitNotSupported() {
        return new Promise((_resolve, reject) => {
            reject(new common_1.NotSupportedError("Not supported"));
        });
    }
});
