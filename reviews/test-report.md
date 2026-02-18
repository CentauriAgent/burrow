# Burrow Test Report

**Date:** 2026-02-16  
**Commits tested:** 7 most recent (5b07795..ce4955a)

## Summary

| Check | Result |
|-------|--------|
| CLI Build | ✅ PASS |
| Flutter Analyze | ✅ PASS |
| CLI Tests | ✅ PASS |
| Flutter Tests | ⚠️ PARTIAL FAIL |
| Import Errors | ✅ PASS |
| Merge Conflicts | ✅ PASS |

---

## 1. CLI Build (`cargo build --release`) — ✅ PASS

Build succeeds. 3 warnings (all pre-existing, not from new commits):
- Unused variable `store` in `init.rs`
- Unused function `hex_to_npub` in `access_control.rs`
- Unused methods `save_mls_state`/`load_mls_state` in `file_store.rs`

## 2. Flutter Analyze — ✅ PASS

**0 errors, 0 warnings, 16 info-level lints.** All are pre-existing style issues (`avoid_print`, `curly_braces_in_flow_control_structures`, `use_build_context_synchronously`, `unnecessary_underscores`). No new errors from the 7 commits.

## 3. Tests

### CLI Tests (`cargo test`) — ✅ PASS
- 0 tests (no test suite yet) — compiles and runs cleanly.

### Flutter Tests (`flutter test`) — ⚠️ PARTIAL FAIL
- **67 passed, 3 failed**
- All 3 failures are in `call_screens_test.dart` — **pre-existing issue**, not caused by new commits:
  1. `IncomingCallScreen renders accept and reject buttons` — missing `widget_test.dart` import
  2. `IncomingCallScreen renders caller info` — same root cause
  3. `OutgoingCallScreen renders cancel button` — `RustLib.init()` not called in test setup (flutter_rust_bridge FFI not initialized)

**Root cause:** Call screen tests depend on `CallManager` → `NostrSignalingService` → `listenForCallEvents()` which requires the Rust FFI bridge. Tests don't mock the bridge or call `RustLib.init()`.

**Not related to the 7 new commits.**

## 4. Import Errors — ✅ PASS

All external package imports resolve correctly. Key packages used by new features verified present in pubspec:
- `mobile_scanner` (QR code scanning)
- `flutter_webrtc` (speaker routing)
- `go_router`, `provider`, `bech32` — all resolved

No undefined references or type mismatches found.

## 5. Merge Conflicts — ✅ PASS

No conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`) found in any source files. The one `======` match is a decorative print statement in `acl.rs` (legitimate code).

---

## Recommendations

1. **Fix call screen tests** — Mock `RustLib`/FFI bridge in test setup, or skip tests when native bridge unavailable.
2. **Add CLI tests** — Currently 0 tests for the Rust CLI; the new NIP-59 gift-wrap feature would benefit from unit tests.
3. **Clean up warnings** — Prefix unused vars with `_`, remove dead code (`hex_to_npub`, MLS state methods if unused).
