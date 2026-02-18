# Code Review: Burrow — Last 7 Commits (2026-02-16)

**Reviewer:** Centauri (Code Review Agent)  
**Date:** 2026-02-16  
**Commits reviewed:** `5b07795` through `ce4955a`

---

## Summary

7 feature commits adding: NIP-59 gift-wrap for invites, mute/unmute, voice recording, in-chat search, contact list, QR scanning, call UI buttons, speaker routing, and configurable TURN servers. Overall quality is solid — idiomatic Dart/Flutter, consistent with existing patterns. Several issues found, ranging from a **critical** mismatched commit to minor race conditions.

---

## Commit-by-Commit Review

### 1. `5b07795` — NIP-59 gift-wrap for invite welcome messages

**File:** `cli/src/commands/invite.rs`

| Severity | Issue |
|----------|-------|
| **Minor** | No retry logic on `client.send_event()`. If the relay is temporarily unreachable, the invite silently fails after the MLS commit has already been merged (line 68). The group state advances but the invitee never receives the Welcome. |
| **Minor** | `iter().flatten()` on `welcome_rumors` — if `welcome_rumors` is `None` (not just empty), this silently skips. Should log a warning since having no Welcome after a successful Add is unexpected. |
| **Nit** | Printing only first 12 chars of hex — consistent with rest of codebase, good. |

**Verdict:** Clean implementation. The MLS-commit-before-send ordering is the main risk — if send fails, the group is in an inconsistent state.

---

### 2. `2105189` — Mute/unmute + voice recording + in-chat search + contacts tab

**This is a massive commit bundling 4+ features.** Should have been separate commits.

#### `app/lib/providers/mute_provider.dart` (new file)

| Severity | Issue |
|----------|-------|
| **Major** | **Race condition in `build()`.** `_load()` is async but `build()` returns `{}` synchronously. Until `_load()` completes, the state is empty — any `isMuted()` check returns false. On app start, muted conversations briefly appear unmuted. Should use `AsyncNotifier` or block on initial load. |
| **Minor** | `unmute()` uses `.where().toSet()` instead of simply `{...state}..remove(groupId)` — works but unnecessarily allocates an intermediate iterable. |

#### `app/lib/screens/chat_list_screen.dart` — Contacts tab

| Severity | Issue |
|----------|-------|
| **Minor** | `ref.watch(muteProvider)` is called inside `itemBuilder` (line ~195). This is fine for Riverpod but watching inside a builder means the entire list rebuilds on any mute change. Should watch once outside the builder. |
| **Nit** | Contact avatar `NetworkImage` — no error handling for broken image URLs. Consider `onError` or `errorBuilder`. |
| **Nit** | Duplicated avatar + fallback-letter logic between `_buildContactsTab` and `_showContactProfile`. Extract to a shared widget. |

#### `app/lib/screens/chat_view_screen.dart` — Search + voice recording + mute

| Severity | Issue |
|----------|-------|
| **Critical** | **Dangling code in diff.** The commit adds dead code at the bottom of the file (lines after `_shortenPubkey`) that duplicates `_startCall`, `_initials`, `_shortenPubkey` — appears to be a merge/rebase artifact. This code was then cleaned up in the *next* commit (`95108de`), but it means this commit doesn't compile cleanly on its own. |
| **Major** | **`_scrollToMatch` uses hardcoded `72.0` pixel estimate per item** (line ~`_scrollToMatch`). Chat bubbles vary wildly in height (text length, images, voice messages). This will scroll to wrong positions for long messages or media. Should use `ScrollablePositionedList` or `GlobalKey`-based scrolling. |
| **Major** | **`_cancelRecording` is `void` but calls `await`** — it's declared `void _cancelRecording() async`. Should be `Future<void>` to avoid unhandled future errors. |
| **Minor** | `_audioRecorder.dispose()` in `dispose()` — the `record` package's `AudioRecorder.dispose()` is async but called without `await`. Could leak native resources on quick navigation. |
| **Minor** | Voice message uses `addIncomingMessage` (line in `_stopAndSendVoiceMessage`) — naming suggests it's for messages from others, not self-sent messages. Verify this correctly marks the message as "mine" in the UI. |
| **Minor** | Search navigation buttons: "Previous" triggers `+1` delta and "Next" triggers `-1` delta. With a reversed `ListView`, this may be correct, but it's confusing. Add a comment explaining the reversal. |
| **Nit** | `ref.read(muteProvider)` in popup menu item build — this is inside a `build()` method but uses `read` instead of `watch`. The menu won't update if mute state changes while the menu is open (unlikely but inconsistent). |

#### `app/lib/widgets/chat_list_tile.dart`

| Severity | Issue |
|----------|-------|
| **Nit** | Mute icon placed between timestamp and unread badge. Consider placing it *next to* the name instead, matching Signal's pattern. |

---

### 3. `95108de` — "QR code scanning" (actually: cleanup + audio widget)

| Severity | Issue |
|----------|-------|
| **Major** | **Commit message is misleading.** Says "implement QR code scanning" but the diff only: (1) removes the dead code from the previous commit, (2) adds `_AudioAttachmentWidget` to `chat_bubble.dart`, (3) adds `just_audio`, `record`, `mobile_scanner` to pubspec. The actual QR scanner screen (`import_identity_screen.dart`) was added in a much older commit. This is a **misattributed squash** — the commit message doesn't match the code. |
| **Minor** | `_AudioAttachmentWidgetState._download()` — downloads and decrypts audio eagerly on widget init. For a chat with many voice messages, this triggers parallel downloads of all visible audio files. Should download on-demand (when play is tapped). |
| **Minor** | Audio `Slider` max value uses `.clamp(1, double.infinity)` — if duration is 0 (metadata not yet loaded), the slider max is 1ms. User could interact with it in this brief window and seek to an invalid position. |
| **Nit** | `_fmt` method duplicates `_formatDuration` from `chat_view_screen.dart`. Extract to a shared utility. |

---

### 4. `ae43687` — Contact list provider

**File:** `app/lib/providers/contacts_provider.dart` (new file)

| Severity | Issue |
|----------|-------|
| **Major** | **N+1 query pattern.** For every group, calls `getGroupMembers()`, then for each member potentially calls `getCachedProfile()`. With 10 groups × 10 members = up to 100 FFI calls. This will be slow on large accounts. Should batch-fetch profiles. |
| **Minor** | Empty `catch (_) {}` blocks (lines 54, 66) swallow all errors silently. At minimum log them for debugging. |
| **Minor** | `FutureProvider` doesn't auto-refresh when groups change. If a new group is joined, contacts won't update until the provider is manually invalidated or the screen is revisited. Consider using `ref.watch(groupsProvider)` reactivity more carefully (it does watch it, but since it's a `FutureProvider` not an `AsyncNotifierProvider`, it won't stream updates). |
| **Nit** | `Contact` class could be a `freezed` class for consistency with other models in the codebase. |

---

### 5. `5ea77e6` — Speaker routing

**File:** `app/lib/providers/call_provider.dart`

| Severity | Issue |
|----------|-------|
| **Minor** | `Helper.setSpeakerphoneOn(useSpeaker)` in the `'active'` case (line ~138) is called without `await`. If it fails, the state shows speaker on but audio routes to earpiece. The `toggleSpeaker()` method correctly handles this with try/catch + revert, but the initial set doesn't. |
| **Nit** | `toggleSpeaker()` changed from `void` to `Future<void>` — good. Verify all call sites `await` or properly handle the future. |

**Verdict:** Clean, minimal change. Good error recovery pattern in `toggleSpeaker()`.

---

### 6. `00250f7` — Call buttons on group info screen

**File:** `app/lib/screens/group_info_screen.dart`

| Severity | Issue |
|----------|-------|
| **Minor** | `_startCall` accesses `_group` directly (a nullable field). If called during a race where group data hasn't loaded yet, it silently returns. Consider showing a snackbar for this edge case. |
| **Minor** | `callId` generated from `DateTime.now().millisecondsSinceEpoch.toRadixString(36)` — not globally unique. Two users starting calls at the same millisecond get the same ID. Use a UUID or add the local pubkey as a prefix. |
| **Nit** | `remoteName: group.dmPeerDisplayName ?? group.name` — good fallback chain. |

**Verdict:** Straightforward feature addition, well-integrated.

---

### 7. `ce4955a` — Configurable TURN server

**Files:** `app/lib/services/turn_settings.dart` (new), `app/lib/services/webrtc_service.dart`, `app/rust/src/api/call_webrtc.rs`

| Severity | Issue |
|----------|-------|
| **Major** | **Hardcoded TURN credentials for `openrelay.metered.ca`** in Rust code (`call_webrtc.rs`). The username is derived from `call_id` and credential from a static seed `"burrow-turn-credential-v1"`. OpenRelay.metered.ca requires actual API-key-based credentials from their dashboard — these generated credentials won't authenticate. This TURN server will fail at runtime. |
| **Minor** | `TurnSettings.load()` is called on every peer connection creation (`await TurnSettings.load()`). SharedPreferences access is fast but still async I/O on every call. Consider caching in memory. |
| **Minor** | STUN vs TURN detection in `webrtc_service.dart` line ~89: `iceServers.where((s) => s['username'] == null)` assumes all TURN servers have usernames and all STUN servers don't. This is generally true but fragile — a TURN server without auth would be kept as "STUN". |
| **Nit** | `TurnConfig.urls` is `List<String>` but stored as comma-separated string. Edge case: a URL containing a comma would break parsing. Use `setStringList` instead. |

**Verdict:** Good architecture (configurable override pattern), but the default TURN server won't work as-is.

---

## Cross-Cutting Concerns

| Severity | Issue |
|----------|-------|
| **Major** | **Commit hygiene.** Commit `2105189` bundles mute, voice recording, search, and contacts tab into one commit. Commit `95108de` has a completely wrong commit message. This makes bisecting and reverting individual features impossible. |
| **Minor** | **No tests added** for any of the 7 commits. `MuteNotifier`, `TurnSettings`, `Contact` model, and `contactsProvider` are all easily unit-testable. |
| **Minor** | **New dependencies** (`record`, `just_audio`, `mobile_scanner`) added without version pinning discussion. `mobile_scanner: ^6.0.2` resolved to `6.0.11` — verify compatibility. |

---

## Summary Table

| Severity | Count |
|----------|-------|
| Critical | 1 (dangling code / broken intermediate commit) |
| Major | 6 (mute race condition, scroll estimation, misleading commit, N+1 queries, TURN auth, commit hygiene) |
| Minor | 14 |
| Nit | 8 |

---

## Recommendations

1. **Split `2105189`** into separate commits for mute, voice recording, search, and contacts tab.
2. **Fix `MuteNotifier`** to use `AsyncNotifier` or ensure initial load completes before first read.
3. **Fix TURN server credentials** — either use a real metered.ca API key or switch to a self-hosted TURN (coturn).
4. **Add unit tests** for at least `MuteNotifier`, `TurnSettings`, and `contactsProvider`.
5. **Fix `_cancelRecording`** return type to `Future<void>`.
6. **Batch profile fetching** in contacts provider to avoid N+1 pattern.
7. **Fix commit `95108de` message** via `git rebase -i` before merging to main.
