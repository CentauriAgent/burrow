# Burrow Security Review

**Date:** 2026-02-12  
**Reviewer:** Centauri (automated security agent)  
**Scope:** Full source review of `src/`, `test/`, `package.json`, dependency audit  
**Version:** 0.1.0

---

## Summary

Burrow is an early-stage E2EE messaging CLI implementing the Marmot protocol (MLS over Nostr). The crypto foundations are sound — it uses reputable libraries (`@noble/curves`, `@noble/hashes`, `nostr-tools`, `ts-mls`) and follows the MIP specifications correctly. However, several issues need attention before any production use.

**Critical:** 1 | **High:** 3 | **Medium:** 4 | **Low:** 3 | **Info:** 2

---

## Critical

### C-1: Private KeyPackage init_key stored as plaintext JSON on disk
**File:** `src/store/index.ts`, `src/cli/init.ts`  
**Description:** `StoredKeyPackage.privateKey` contains the MLS private init key material, stored as plaintext base64 in a JSON file under `~/.burrow/keypackages/`. The data directory (`~/.burrow/`) is created with default permissions (0o775), meaning other users on a shared system can read private key material. Only the secret key file itself is written with `mode: 0o600`.  
**Impact:** Any local user or process can read MLS private keys, enabling decryption of Welcome messages and impersonation.  
**Remediation:**
1. Set `~/.burrow/` directory permissions to `0o700` on creation
2. Write all files containing key material with `mode: 0o600`
3. Consider encrypting key material at rest (e.g., using a passphrase-derived key)

---

## High

### H-1: No zeroization of secret key material in memory
**Files:** `src/crypto/identity.ts`, `src/crypto/nip44.ts`, `src/mls/group.ts`  
**Description:** Secret keys (`secretKey`, `exporterSecret`, ephemeral keys) are held in `Uint8Array` buffers that are never zeroed after use. JavaScript's GC will eventually collect them, but the memory may persist for an indeterminate time. The `NostrIdentity` object stores both `secretKey` and `secretKeyHex` as long-lived properties.  
**Impact:** Secret key material remains in process memory longer than necessary, increasing exposure window for memory dumps or side-channel attacks.  
**Remediation:**
1. Zero `Uint8Array` buffers after use: `secretKey.fill(0)`
2. Avoid storing `secretKeyHex` as a persistent property — derive on demand
3. Consider using `crypto.subtle` for key operations where possible (keys stay in secure memory)

### H-2: Ephemeral key for group events not truly ephemeral — leaks via `randomBytes`
**File:** `src/nostr/relay.ts` → `createEphemeralSignedEvent()`  
**Description:** The ephemeral secret key is generated and returned from the function but never zeroed. The caller (`buildGroupEvent`) returns it as part of the result, and `sendCommand` never zeros it. Additionally, `randomBytes` from Node.js crypto is CSPRNG-quality, but the key is unnecessarily kept alive.  
**Impact:** Ephemeral keys meant for single-use metadata protection remain in memory.  
**Remediation:** Zero the ephemeral secret after event signing. Do not return it from `buildGroupEvent` unless needed.

### H-3: `node_modules/` committed to git repository
**File:** `.gitignore` (missing), `node_modules/`  
**Description:** 2,614 files from `node_modules/` are tracked in git. No `.gitignore` file exists. This bloats the repository, may include platform-specific binaries, and makes dependency auditing harder.  
**Impact:** Repository bloat, potential inclusion of vulnerable dependency versions without lockfile-based auditing, harder code review.  
**Remediation:** ✅ **Fixed in this commit** — added `.gitignore` and removed `node_modules` from git tracking.

---

## Medium

### M-1: Store directory permissions too permissive
**File:** `src/store/index.ts`  
**Description:** `BurrowStore` constructor creates directories with `mkdirSync(..., { recursive: true })` using default permissions (typically 0o755). The `groups/`, `keypackages/`, `mls-state/`, and `messages/` directories contain sensitive data including MLS group state (which contains epoch secrets).  
**Remediation:** Pass `{ recursive: true, mode: 0o700 }` to all `mkdirSync` calls in the store.

### M-2: No input validation on invitee pubkey or group ID
**Files:** `src/cli/invite.ts`, `src/cli/send.ts`, `src/cli/read.ts`  
**Description:** User-supplied `groupId` and `inviteePubkey` are used directly in file paths (`store.getGroup(opts.groupId)`) and relay queries without validation. A crafted group ID like `../../etc/passwd` could potentially cause path traversal in the store.  
**Impact:** Path traversal in file-based store; malformed pubkeys could cause cryptographic errors.  
**Remediation:**
1. Validate group IDs are hex strings of expected length
2. Validate pubkeys are 64-char hex strings
3. Sanitize file paths in `BurrowStore` (reject `/`, `..`, etc.)

### M-3: MLS group state stored unencrypted
**File:** `src/store/index.ts` → `saveMlsState()`  
**Description:** The serialized MLS `GroupState` is written as raw binary to `~/.burrow/mls-state/<groupId>.bin`. This state contains the full MLS key schedule including `encryption_secret`, `exporter_secret`, and `epoch_secret`. Anyone who can read this file can decrypt all group messages for the current epoch.  
**Remediation:** Encrypt MLS state at rest using a key derived from the user's Nostr secret key.

### M-4: `require()` used in ESM module for dynamic imports
**Files:** `src/crypto/identity.ts` (line with `require('nostr-tools')`), `src/nostr/relay.ts`  
**Description:** Mixed ESM (`import`) and CJS (`require()`) patterns. While not directly a security issue, this can cause module resolution failures in strict ESM environments and makes the codebase harder to audit. The `require('nostr-tools')` in `identity.ts` for nsec decoding is a runtime dynamic import that bypasses static analysis.  
**Remediation:** Replace `require()` with dynamic `await import()` consistently.

---

## Low

### L-1: No KeyPackage expiration or rotation
**Files:** `src/mls/keypackage.ts`, `src/cli/init.ts`  
**Description:** KeyPackages are generated with `defaultLifetime` from ts-mls but there's no mechanism to rotate or expire them. Old KeyPackages remain valid indefinitely on relays. The "last resort" flag is always set, meaning the same KeyPackage can be reused for multiple group invitations.  
**Impact:** Reduced forward secrecy; compromised init_key affects all groups joined with that KeyPackage.  
**Remediation:** Implement KeyPackage rotation (publish new, delete old). Generate non-last-resort packages for normal use.

### L-2: No signature verification on incoming events in `listenCommand`
**File:** `src/cli/read.ts` → `listenCommand()`  
**Description:** Incoming kind 445 events from relays are processed without verifying the Nostr signature. While the MLS layer provides its own authentication, an attacker could craft events that cause unnecessary MLS processing or error logging.  
**Remediation:** Verify event signatures before attempting MLS decryption.

### L-3: Inner event sender pubkey not verified against MLS leaf
**File:** `src/cli/read.ts` → `listenCommand()`  
**Description:** After decrypting an MLS application message, the inner kind 9 event's `pubkey` field is trusted without verifying it matches the MLS leaf node credential of the sender. A compromised group member could forge messages appearing to come from another member.  
**Impact:** Message attribution spoofing within a group.  
**Remediation:** After MLS decryption, verify `innerEvent.pubkey` matches the sender's MLS BasicCredential identity.

---

## Info

### I-1: Dependency audit — all crypto dependencies are reputable
**Assessment:**
| Dependency | Version | Status |
|---|---|---|
| `@noble/curves` | ^2.0.1 | ✅ Audited, widely used, by paulmillr |
| `@noble/hashes` | ^2.0.1 | ✅ Audited, widely used, by paulmillr |
| `nostr-tools` | ^2.23.1 | ✅ Standard Nostr library, active maintenance |
| `ts-mls` | ^1.6.1 | ⚠️ Smaller project, less audit history — monitor |
| `websocket-polyfill` | ^1.0.0 | ✅ Utility, no crypto |
| `commander` | ^14.0.3 | ✅ CLI framework, no crypto |

All crypto deps use `^` semver ranges. Consider pinning exact versions for reproducible builds. `ts-mls` is the least audited dependency — its correctness is critical for MLS security.

### I-2: Test coverage is good but lacks adversarial tests
**Assessment:** Tests cover happy-path crypto roundtrips, extension encoding, event building, and store operations. Missing:
- Malformed input handling (truncated ciphertext, invalid base64, oversized messages)
- Boundary conditions (max message size, empty groups)
- Adversarial MLS messages (replayed commits, out-of-order epochs)

---

## Positive Findings

1. **NIP-44 usage is correct** — conversation keys derived properly, random nonces used (no reuse risk)
2. **Ephemeral keys for group events** — good metadata protection per MIP-03
3. **Inner events unsigned** — correctly follows MIP-03 security requirement (prevents signature correlation)
4. **Secret key file written with 0o600** — correct for the key file itself
5. **NIP-70 tag on KeyPackage events** — prevents relay tampering
6. **Gift-wrapping for Welcome events** — proper NIP-59 privacy for invitations
7. **Ciphersuite choice** — X25519/AES-128-GCM/SHA-256/Ed25519 is the standard MLS ciphersuite
