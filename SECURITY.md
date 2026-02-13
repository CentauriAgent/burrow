# Burrow Security Review

## Phase 1 Review (2026-02-12) — TypeScript CLI

**Reviewer:** Centauri (automated security agent)  
**Scope:** Full source review of `src/`, `test/`, `package.json`, dependency audit  
**Version:** 0.1.0

### Summary

Burrow is an early-stage E2EE messaging CLI implementing the Marmot protocol (MLS over Nostr). The crypto foundations are sound — it uses reputable libraries (`@noble/curves`, `@noble/hashes`, `nostr-tools`, `ts-mls`) and follows the MIP specifications correctly.

**Critical:** 1 | **High:** 3 | **Medium:** 4 | **Low:** 3 | **Info:** 2

### Phase 1 Findings (see git history for full detail)

| ID | Severity | Issue | Phase 2 Status |
|---|---|---|---|
| C-1 | Critical | Private KeyPackage init_key stored as plaintext JSON | **Mitigated** — Phase 2 uses `MdkMemoryStorage` (in-memory only); file save now uses 0o600 perms |
| H-1 | High | No zeroization of secret key material in memory | **Open** — Rust `Keys` struct does not implement `Zeroize`; see P2-H1 |
| H-2 | High | Ephemeral key not zeroed after use | **Mitigated** — MDK handles ephemeral keys internally |
| H-3 | High | `node_modules/` committed to git | **Fixed** in Phase 1 |
| M-1 | Medium | Store directory permissions too permissive (0o755) | **Fixed** — `save_secret_key` now sets 0o700 on dir, 0o600 on file |
| M-2 | Medium | No input validation on group ID / pubkey (path traversal) | **Mitigated** — Phase 2 validates hex in all ID params; path traversal blocked on file ops |
| M-3 | Medium | MLS group state stored unencrypted | **Mitigated** — Phase 2 uses `MdkMemoryStorage` (RAM only, no disk persistence yet) |
| M-4 | Medium | Mixed ESM/CJS `require()` | **N/A** — Phase 2 is Rust, not TypeScript |
| L-1 | Low | No KeyPackage expiration/rotation | **Open** — not yet implemented |
| L-2 | Low | No signature verification on incoming events | **Delegated** — `nostr-sdk` verifies signatures on fetch; MDK handles MLS auth |
| L-3 | Low | Inner event sender not verified against MLS leaf | **Delegated** — MDK `process_message` handles sender binding |

---

## Phase 2 Review (2026-02-12) — Flutter + Rust (MDK)

**Reviewer:** Centauri (automated security agent)  
**Scope:** Full source review of `app/rust/src/api/`, `app/lib/`, `Cargo.toml`, CI pipeline  
**Version:** 0.1.0 (Flutter + Rust rewrite using Marmot Developer Kit)

### Architecture Changes

Phase 2 replaces the TypeScript CLI with a Flutter app backed by Rust via `flutter_rust_bridge`. The core MLS protocol logic is now delegated to **MDK (Marmot Developer Kit)** — a Rust library implementing the Marmot protocol. This significantly improves the security posture:

- MLS state management, key schedules, and message encryption/decryption are handled by MDK
- Storage is currently `MdkMemoryStorage` (in-memory only — no disk persistence of MLS state)
- Nostr event handling uses `nostr-sdk` (mature, well-tested)

### Findings

#### P2-H1: No memory zeroization of `Keys` on logout [HIGH]
**File:** `app/rust/src/api/state.rs` → `destroy_state()`  
**Description:** `destroy_state()` sets the global state to `None`, which drops the `BurrowState` struct. However, the `nostr_sdk::Keys` struct holds the secret key in memory and does not implement the `Zeroize` trait. When dropped, the memory containing the secret key is deallocated but not zeroed — it may persist until overwritten by new allocations.  
**Impact:** Secret key material remains in process memory after logout.  
**Status:** **Open** — `nostr_sdk::Keys` does not expose zeroization. Filed as upstream concern. The `MdkMemoryStorage` also holds MLS key material that is not zeroed on drop.  
**Mitigation:** This is a defense-in-depth issue. On mobile, app process isolation limits the attack surface. Consider contributing `Zeroize` support upstream to `nostr-sdk`.

#### P2-H2: Blossom media upload has no authentication [HIGH]
**File:** `app/rust/src/api/media.rs` → `upload_media()`  
**Description:** The HTTP PUT to the Blossom server includes no authentication header. NIP-98 HTTP Auth should be used to prove the uploader's identity and prevent unauthorized uploads or content injection.  
**Impact:** Any client can upload content to the Blossom server; no proof of authorship.  
**Status:** **Open** — requires NIP-98 event creation and inclusion as `Authorization` header.

#### P2-M1: Downloaded media not verified against content hash [MEDIUM]
**File:** `app/rust/src/api/media.rs` → `download_media()`  
**Description:** Encrypted media downloaded from Blossom URLs was not verified against the expected SHA-256 hash before decryption.  
**Impact:** A MITM or compromised Blossom server could serve tampered ciphertext. While ChaCha20-Poly1305 would reject tampered data during decryption, verifying the hash first provides defense in depth and clearer error messages.  
**Status:** ✅ **Fixed** — Added SHA-256 hash verification of downloaded data against URL hash before decryption.

#### P2-M2: `save_secret_key` wrote file with default permissions [MEDIUM]
**File:** `app/rust/src/api/account.rs`  
**Description:** `save_secret_key` used `std::fs::write()` which creates files with default permissions (typically 0o644), exposing the nsec to other users on the system.  
**Status:** ✅ **Fixed** — Now sets 0o600 on file and 0o700 on parent directory. Also added path traversal rejection.

#### P2-M3: No path traversal protection on file operations [MEDIUM]
**Files:** `app/rust/src/api/account.rs` → `save_secret_key`, `load_account_from_file`  
**Description:** User-supplied file paths were used directly without validation.  
**Status:** ✅ **Fixed** — Both functions now reject paths containing `..`.

#### P2-L1: No `cargo audit` in CI pipeline [LOW]
**File:** `.github/workflows/ci.yml`  
**Description:** CI runs fmt, clippy, and tests but does not audit dependencies for known vulnerabilities.  
**Status:** ✅ **Fixed** — Added `rust-audit` job to CI pipeline.

#### P2-L2: No KeyPackage rotation mechanism [LOW]
**File:** `app/rust/src/api/keypackage.rs`  
**Description:** KeyPackages are generated and published but there's no mechanism for rotation or expiration enforcement.  
**Status:** **Open** — deferred to Phase 3.

#### P2-L3: `fetch_key_package` uses `block_on` inside async context [LOW]
**File:** `app/rust/src/api/invite.rs` → `fetch_key_package()`  
**Description:** Uses `rt.block_on()` inside `with_state()` which holds an async `RwLock` read guard. This could deadlock if the tokio runtime has limited threads. Same pattern in `relay.rs`.  
**Status:** **Open** — works with multi-thread runtime but should be refactored to use proper async flow.

### Positive Findings

1. **MDK delegation** — Core MLS protocol logic (key schedules, encryption, state management) is handled by MDK, reducing custom crypto code
2. **`MdkMemoryStorage`** — No MLS state written to disk (yet), eliminating disk-based key exposure
3. **`rustls-tls`** — reqwest configured with `rustls-tls` feature, ensuring TLS for all HTTP connections with proper certificate validation
4. **`nostr-sdk` handles Nostr crypto** — Key parsing, event signing, and signature verification use the well-tested `nostr-sdk` library
5. **Flutter nsec input uses `obscureText`** — Import identity screen properly obscures the secret key field
6. **No key logging** — No `print`/`log`/`debug` statements expose key material in Dart or Rust code
7. **ChaCha20-Poly1305 for media** — MIP-04 v2 media encryption uses authenticated encryption (AEAD)
8. **imeta tag validation** — `parse_imeta_tag` validates hash length (32 bytes) and nonce length (12 bytes)
9. **Hex validation on all IDs** — Group IDs, pubkeys, and event IDs are parsed through proper hex/bech32 decoders
10. **Default relays use WSS** — All default relay URLs use `wss://` (TLS)

### Dependency Assessment

| Dependency | Version | Assessment |
|---|---|---|
| `mdk-core` | git pin (5ef0c60) | ⚠️ Pinned to specific rev — good for reproducibility. MDK is by the Marmot protocol team. Less audit history than nostr-sdk. |
| `nostr-sdk` | 0.44 | ✅ Widely used, actively maintained |
| `reqwest` | 0.12 (rustls-tls) | ✅ Standard HTTP client, using rustls for TLS |
| `flutter_rust_bridge` | 2.11.1 (pinned) | ✅ Active project, pinned exact version |
| `sha2` | 0.10 | ✅ RustCrypto, widely audited |
| `hex` | 0.4 | ✅ Utility crate |

### Recommendations for Phase 3

1. **Persistent storage encryption** — When moving from `MdkMemoryStorage` to disk-backed storage, encrypt at rest using a key derived from the user's secret key or platform keychain
2. **NIP-98 auth for Blossom** — Add HTTP Auth headers to media uploads
3. **Upstream `Zeroize`** — Request/contribute `Zeroize` trait implementation for `nostr_sdk::Keys`
4. **KeyPackage rotation** — Implement automatic rotation with configurable lifetime
5. **Refactor async patterns** — Remove `block_on` inside async RwLock guards to prevent potential deadlocks
6. **Platform keychain integration** — Use iOS Keychain / Android Keystore for secret key storage instead of plain files
7. **Add adversarial tests** — Malformed events, truncated ciphertext, replayed messages
