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
- [x] 2.1 Typing indicators (ephemeral MLS app messages + UI)
- [x] 2.2 @Mention autocomplete (`@` trigger, member list popup, npub resolution)

### Batch 3: Rich Content (moderate effort)
- [x] 3.1 Polls (custom message kind, vote tracking, tally UI)

### Batch 4: Push Notifications (large effort, platform-specific)
- [ ] 4.1 Firebase Cloud Messaging setup (Android)
- [ ] 4.2 APNs setup (iOS)
- [ ] 4.3 Notification server (receives from relays, pushes to devices)
- [ ] 4.4 Background message decryption

### Batch 5: CLI Agent Audio Calls (large effort, new capability)
- [x] 5.1 Call signaling in CLI (NIP-59 gift-wrapped, kinds 25050-25054)
- [x] 5.2 Headless WebRTC in Rust (GStreamer webrtcbin + Opus)
- [x] 5.3 Audio I/O (PulseAudio/PipeWire + pipe mode for agent)
- [x] 5.4 Agent integration: --pipe flag for raw PCM STT/TTS
- [ ] 5.5 End-to-end test with Flutter app

## Decisions Made
- Agent calls: audio-only (listen + speak), no video needed
- Implementation order: quick wins first, then messaging UX, then heavy lifts
- Interactive widgets (HTML): deprioritized (even Pika only has iOS)

## Status
**Batches 1-3, 5 complete** — Batch 4 (push notifications) skipped for now. Batch 5 needs build+test on CLI machine.
