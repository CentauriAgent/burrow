# Task Plan: Pika Feature Parity

## Goal
Implement all missing features to reach parity with Pika, plus CLI audio call support for AI agents.

## Phases

### Batch 1: Quick Wins (small effort, immediate UX improvement)
- [x] 1.1 Markdown rendering in chat bubbles (`flutter_markdown`)
- [x] 1.2 QR code display for npub sharing (`qr_flutter`)
- [x] 1.3 Follow/unfollow contacts (publish NIP-02 kind 3 events)
- [x] 1.4 Personal profile photo upload (reuse Blossom from group avatars)

### Batch 2: Messaging UX (moderate effort)
- [ ] 2.1 Typing indicators (ephemeral MLS app messages + UI)
- [ ] 2.2 @Mention autocomplete (`@` trigger, member list popup, npub resolution)

### Batch 3: Rich Content (moderate effort)
- [ ] 3.1 Polls (custom message kind, vote tracking, tally UI)

### Batch 4: Push Notifications (large effort, platform-specific)
- [ ] 4.1 Firebase Cloud Messaging setup (Android)
- [ ] 4.2 APNs setup (iOS)
- [ ] 4.3 Notification server (receives from relays, pushes to devices)
- [ ] 4.4 Background message decryption

### Batch 5: CLI Agent Audio Calls (large effort, new capability)
- [ ] 5.1 Call signaling in CLI (Nostr-based offer/answer/ICE, MLS-encrypted)
- [ ] 5.2 Headless WebRTC in Rust (libwebrtc or GStreamer)
- [ ] 5.3 Audio I/O via cpal (capture mic / playback speaker)
- [ ] 5.4 Agent integration: stdin/stdout audio pipes for STT/TTS

## Decisions Made
- Agent calls: audio-only (listen + speak), no video needed
- Implementation order: quick wins first, then messaging UX, then heavy lifts
- Interactive widgets (HTML): deprioritized (even Pika only has iOS)

## Status
**Batch 1 complete** - Moving to Batch 2 (typing indicators, mentions)
