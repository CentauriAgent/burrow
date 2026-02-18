# Security Audit — Burrow Recent Commits

**Date:** 2026-02-16  
**Scope:** 7 commits (5b07795..ce4955a) — ~2 hours of development  
**Auditor:** Centauri (Security Sub-agent)

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 2 |
| Medium | 3 |
| Low | 2 |
| Informational | 3 |

---

## Critical

### C-1: Hardcoded TURN credential derivation salt — deterministic credentials without server auth
**Commit:** ce4955a (`call_webrtc.rs`)  
**File:** `app/rust/src/api/call_webrtc.rs`

TURN credentials are derived client-side using `SHA256("burrow-turn-credential-v1" || call_id)`. This is a **static, publicly-visible derivation scheme** — anyone who knows the call_id can compute the same credential. The salt `burrow-turn-credential-v1` is hardcoded in the binary.

Against the default `openrelay.metered.ca` server, these credentials are meaningless (metered.ca uses its own API key auth), so the generated username/credential pair will likely be **rejected**, causing TURN fallback failure (calls won't work behind symmetric NATs).

If a self-hosted TURN server is configured that trusts these credentials, any party with the call_id can authenticate — the credential provides no actual access control.

**Impact:** Calls may silently fail (no working TURN), or if a matching TURN server is deployed, credentials are trivially forgeable.  
**Recommendation:**
- Use a proper TURN credential server (e.g., coturn REST API with shared secret + time-limited credentials)
- Or use metered.ca's API to fetch real credentials at call time
- Remove the fake credential generation entirely

---

## High

### H-1: TURN credentials stored in plaintext SharedPreferences
**Commit:** ce4955a (`turn_settings.dart`)  
**File:** `app/lib/services/turn_settings.dart`

Custom TURN server URL, username, and credential are stored in `SharedPreferences` (unencrypted XML on Android, plist on iOS). On rooted/jailbroken devices or via backup extraction, these credentials are trivially readable.

**Impact:** TURN server credential theft if user configures a private TURN server.  
**Recommendation:** Use `flutter_secure_storage` (Keychain on iOS, EncryptedSharedPreferences on Android) for the credential field at minimum.

### H-2: QR code scanner accepts raw hex private keys without confirmation
**Commit:** 95108de (`import_identity_screen.dart`)  
**File:** `app/lib/screens/import_identity_screen.dart`

The QR scanner auto-imports after a successful scan (`_scanQrCode` → `_import()`). A malicious QR code containing a valid 64-char hex string would immediately trigger key import, replacing the user's identity without confirmation.

The regex `^[0-9a-fA-F]{64}$` correctly validates hex format, and `nsec1` prefix check is correct for bech32. However:
- No confirmation dialog before auto-import
- No warning that current identity will be replaced
- A malicious QR code at a conference/meetup could trick users into importing an attacker-controlled key

**Impact:** Identity replacement attack via social engineering + malicious QR code.  
**Recommendation:** Add a confirmation dialog showing the pubkey derived from the scanned key before importing. Never auto-import.

---

## Medium

### M-1: Contact pubkeys exposed in URL query parameters
**Commit:** 2105189 / ae43687 (`chat_list_screen.dart`)  
**File:** `app/lib/screens/chat_list_screen.dart`

Navigation uses `context.go('/new-dm?pubkey=${contact.pubkeyHex}')` — the full hex pubkey is placed in the route URL. While this is in-app navigation (not a browser URL), Flutter's GoRouter may log routes, and third-party analytics/crash reporting SDKs could capture route strings.

**Impact:** Potential pubkey leakage via logging/analytics.  
**Recommendation:** Pass pubkey via route `extra` parameter instead of query string.

### M-2: Voice message temp files may persist on failure
**Commit:** 2105189 (`chat_view_screen.dart`)  
**File:** `app/lib/screens/chat_view_screen.dart`

Voice recordings are saved to `getTemporaryDirectory()` as `voice_*.m4a`. Cleanup uses `file.delete().catchError((_) => file)` — errors are silently swallowed. If the send fails and cleanup fails, unencrypted audio files persist in the temp directory indefinitely.

**Impact:** Unencrypted voice data may persist on device storage.  
**Recommendation:** Implement periodic temp file cleanup on app startup. Consider encrypting recordings at rest before sending.

### M-3: Downloaded media file permissions not explicitly set
**Commit:** 95108de (audio attachment widget in `chat_bubble.dart`)  
**File:** `app/lib/widgets/chat_bubble.dart`

`MediaAttachmentService.downloadAttachment()` is called to decrypt and save audio files locally. The audit cannot verify the file permissions set by this service from the diff alone, but downloaded decrypted media should use restrictive permissions (0600) to prevent other apps from reading them.

**Impact:** Decrypted media may be accessible to other apps on the device.  
**Recommendation:** Verify `MediaAttachmentService` sets file mode 0600 on downloaded/decrypted files. Use app-private directories.

---

## Low

### L-1: Mute state in SharedPreferences — acceptable but noted
**Commit:** 2105189 (`mute_provider.dart`)  
**File:** `app/lib/providers/mute_provider.dart`

Muted group IDs (MLS group ID hex strings) are stored in SharedPreferences. These are not secret (they're derived from group state), but they do reveal which groups exist on the device.

**Impact:** Minimal — group existence metadata leakage on compromised device.  
**Recommendation:** Acceptable for mute state. No action needed unless threat model includes device forensics.

### L-2: Call ID derived from timestamp — predictable
**Commit:** 00250f7 (`group_info_screen.dart`)  
**File:** `app/lib/screens/group_info_screen.dart`

`DateTime.now().millisecondsSinceEpoch.toRadixString(36)` generates call IDs. These are predictable (timestamp-based) and could allow an observer to guess call IDs and derive TURN credentials (see C-1).

**Impact:** Low independently, amplifies C-1 if TURN credential derivation is fixed but call_id remains predictable.  
**Recommendation:** Use a cryptographic random value (e.g., `Uuid.v4()` or `Random.secure()`).

---

## Informational

### I-1: NIP-59 gift-wrap implementation uses correct library API
**Commit:** 5b07795 (`invite.rs`)  
**File:** `cli/src/commands/invite.rs`

The gift-wrap implementation uses `EventBuilder::gift_wrap(&keys, &invitee_pk, rumor, tags)` from the `nostr` crate, which handles NIP-44 encryption internally. The empty tags vector `Vec::<Tag>::new()` is correct — gift wraps should not leak metadata in outer tags.

**Status:** ✅ Correct. No metadata leaks in the outer event.

### I-2: Camera permission properly scoped
**Commit:** 95108de

Android `CAMERA` permission added to AndroidManifest. iOS `NSCameraUsageDescription` added to Info.plist. The camera is only accessed via `mobile_scanner` for QR scanning — no background camera access, no photo library access for this feature.

**Status:** ✅ Properly scoped.

### I-3: Speaker routing has proper error handling
**Commit:** 5ea77e6 (`call_provider.dart`)

`toggleSpeaker()` reverts state on failure — good defensive pattern. No security impact.

**Status:** ✅ Good practice.

---

## Recommendations Priority

1. **Immediately:** Fix TURN credential system (C-1) — current approach is both insecure and non-functional
2. **Before release:** Move TURN credentials to secure storage (H-1), add QR import confirmation dialog (H-2)
3. **Soon:** Fix pubkey in URL params (M-1), add temp file cleanup (M-2), verify media file permissions (M-3)
4. **Backlog:** Use cryptographic random for call IDs (L-2)
