# Task Plan: CLI Headless Audio Calls

## Goal
Enable the CLI agent to join and participate in real-time audio calls with the Flutter app, using the same Nostr-based signaling and WebRTC stack.

## Architecture

```
CLI Agent                          Flutter App
┌─────────────────┐              ┌──────────────┐
│ call command     │              │ CallManager   │
│  ├─ signaling    │◄──Nostr───►│  ├─ signaling │
│  │  (NIP-59)     │  (kind     │  │  (NIP-59)  │
│  │               │  25050-54) │  │             │
│  ├─ WebRTC       │◄──P2P────►│  ├─ WebRTC    │
│  │  (GStreamer    │  (DTLS/   │  │  (flutter_  │
│  │   webrtcbin)   │  SRTP)    │  │   webrtc)   │
│  │               │            │  │             │
│  └─ Audio I/O    │            │  └─ Audio I/O │
│     (PulseAudio/ │            │     (platform │
│      pipewire/   │            │      native)  │
│      file pipe)  │            │               │
└─────────────────┘              └──────────────┘
```

## Signaling Protocol (reuse from Flutter app)
- Kind 25050: Call Offer (SDP + call_type)
- Kind 25051: Call Answer (SDP)
- Kind 25052: ICE Candidate
- Kind 25053: Hangup
- Kind 25054: State Update (mute/video)
- All NIP-59 gift-wrapped for 1:1 calls
- 60s TTL via expiration tag

## Phases
- [ ] Phase 1: CLI call command scaffold + signaling (Nostr events)
- [ ] Phase 2: GStreamer WebRTC integration (webrtcbin)
- [ ] Phase 3: Audio I/O (PulseAudio/pipewire + file pipe for agent)
- [ ] Phase 4: End-to-end test with Flutter app

## Key Decisions
- GStreamer over webrtc-rs: GStreamer has mature webrtcbin, handles codecs (opus), 
  ICE, DTLS all in one pipeline. webrtc-rs is lower-level and less battle-tested.
- Audio pipe mode: agent can read/write raw PCM from named pipes for STT/TTS
- No video initially (audio-only flag)

## Dependencies
- gstreamer, gstreamer-webrtc, gstreamer-sdp Rust crates
- GStreamer runtime with webrtcbin, opus plugins installed on system
- PulseAudio or PipeWire for mic/speaker (or filesrc/filesink for agent mode)

## Status
**Starting Phase 1** - CLI command scaffold + signaling
