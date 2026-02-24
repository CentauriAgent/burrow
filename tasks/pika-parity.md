# Pika Feature Parity Analysis

## Current State

| # | Feature | Burrow | Pika | Gap |
|---|---------|--------|------|-----|
| 1 | 1:1 Encrypted DMs | YES | YES | None |
| 2 | Group Chats (MLS) | YES | YES | None |
| 3 | Voice Calls (1:1) | YES (WebRTC) | YES (MoQ/QUIC) | Different transport, both work |
| 4 | Video Calls (1:1) | YES (WebRTC) | YES (MoQ/QUIC) | Different transport, both work |
| 5 | Push Notifications | NO | YES (iOS APNs) | **Full gap** |
| 6 | Emoji Reactions | YES | YES | None |
| 7 | Typing Indicators | NO | YES | **Full gap** |
| 8 | @Mention Autocomplete | NO | YES | **Full gap** |
| 9 | Markdown Rendering | NO | YES | **Full gap** |
| 10 | Polls | NO | YES | **Full gap** |
| 11 | Interactive Widgets | NO | YES (iOS) | **Full gap** (low priority) |
| 12 | QR Code Scan/Display | PARTIAL (scan only) | YES | QR display/generation missing |
| 13 | Encrypted Media | YES (MIP-04) | YES | None |
| 14 | Profile Photo Upload | PARTIAL (groups only) | YES | Personal profile upload missing |
| 15 | Follow/Unfollow | PARTIAL (read-only) | YES | Write NIP-02 follow list missing |

## Priority Tiers

### Tier 1: Core Messaging UX (high impact, moderate effort)
- [ ] **Typing Indicators** - Ephemeral MLS app messages, UI "typing..." display
- [ ] **@Mention Autocomplete** - `@` trigger, member list popup, npub resolution
- [ ] **Markdown Rendering** - Add `flutter_markdown` to chat bubbles
- [ ] **QR Code Display** - Add `qr_flutter` for npub sharing

### Tier 2: Engagement Features (high impact, larger effort)
- [ ] **Push Notifications** - Firebase/APNs setup, notification service, background message decryption
- [ ] **Polls** - Custom message kind, vote tracking, tally UI
- [ ] **Profile Photo Upload** - Blossom upload for personal avatar, kind 0 metadata update

### Tier 3: Complete CRUD (moderate impact, small effort)
- [ ] **Follow/Unfollow** - Publish kind 3 events from Burrow
- [ ] **Personal Profile Photo** - Reuse existing Blossom upload from group avatars

### Tier 4: Advanced (low priority)
- [ ] **Interactive Widgets (HTML)** - Webview in chat bubbles, only iOS in Pika

## Architecture Notes

Pika uses a fundamentally different architecture:
- **Native UI** (SwiftUI + Kotlin) vs Burrow's **Flutter**
- **MoQ/QUIC** for calls vs Burrow's **WebRTC**
- **UniFFI** for Rust bindings vs Burrow's **flutter_rust_bridge**
- **Unidirectional state** (Elm-like full snapshots) vs Burrow's **Riverpod providers**

These are valid design divergences, not gaps. Burrow's Flutter approach gives cross-platform coverage from a single codebase. Pika's native approach gives tighter platform integration.

## Key Pika Innovations Worth Studying
1. MoQ (Media over QUIC) for calls - potentially lower latency than WebRTC
2. Notification Service Extension - decrypts MLS in iOS background process
3. MLS-derived media encryption keys for calls (not SRTP/DTLS)
4. Rust-driven navigation router (UI follows state, not vice versa)
