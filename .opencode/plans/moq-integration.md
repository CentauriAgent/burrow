# Burrow MOQ Integration Plan

## Goal
Replace WebRTC with Media over QUIC (MOQ) for audio/video calls, enabling multi-party group calls with Nostr-based signaling and MLS end-to-end encryption.

## Architecture

```
Nostr Relays (signaling)                    MOQ Relay (media)
┌────────────────────────────────┐      ┌───────────────────────────┐
│ Call setup (kind 25050)        │      │ Audio/Video tracks        │
│ Call end (kind 25053)          │      │ per participant           │
│ Mute/camera (kind 25054)      │      │                           │
│ MLS-encrypted for groups       │      │ QUIC transport            │
│                                │      │ MLS-derived frame keys    │
└────────────────────────────────┘      └───────────────────────────┘
         ▲                                        ▲
         │                                        │
    ┌────┴────────────────────────────────────────┴──┐
    │              Burrow Client                      │
    │                                                 │
    │  Flutter: camera/mic capture, UI, render        │
    │  Rust: MOQ transport, encode/decode, MLS        │
    │  Nostr: signaling, relay discovery              │
    └─────────────────────────────────────────────────┘
```

## Nostr Events

### MOQ Relay List (kind 10053) — new replaceable event
```json
{
  "kind": 10053,
  "content": "",
  "tags": [
    ["relay", "moq://moq.burrow.chat:4443"],
    ["relay", "moq://moq.backup.example:4443"]
  ]
}
```

### Revised Call Offer (kind 25050) — no more SDP
```json
{
  "call_id": "abc123",
  "call_type": "audio|video",
  "moq_relay": "moq://moq.burrow.chat:4443",
  "broadcast_path": "burrow/<group_id>/<caller_pubkey_hex>",
  "room": "<group_id>"
}
```

### Relay Selection Logic
1. Check if the group has an admin-configured MOQ relay
2. Fall back to the caller's kind 10053 relay list
3. Fall back to `moq.burrow.chat` default

### Group Call Flow
1. Alice taps "Start Call" → Burrow picks a MOQ relay
2. Alice connects to MOQ relay, publishes her audio/video tracks
3. Alice sends MLS-encrypted call event via Nostr (kind 445 wrapping kind 25050)
4. Bob and Carol see the event → connect to the same MOQ relay
5. Each publishes their own tracks, subscribes to others' tracks
6. Mute/unmute/leave events flow through Nostr (MLS-encrypted kinds 25053/25054)
7. Media frames are E2EE using MLS-derived keys (relay can't decrypt)
8. When everyone hangs up → kind 25053 via Nostr

---

## Phases

- [ ] Phase 0: Infrastructure — deploy moq-relay
- [ ] Phase 1: Rust MOQ transport layer
- [ ] Phase 2: Flutter media capture + render pipeline
- [ ] Phase 3: Rewire call manager + provider
- [ ] Phase 4: Multi-party group calls
- [ ] Phase 5: MOQ relay discovery via Nostr (kind 10053)
- [ ] Phase 6: Production hardening

---

## Phase 0: Infrastructure (Week 1)
*Deploy MOQ relay, no app changes*

| Task | Details |
|------|---------|
| Deploy `moq-relay` to a VPS | Single binary, Let's Encrypt TLS, `moq.burrow.chat:4443` |
| Run in open mode initially | `--auth-public ""` — no JWT auth during development |
| Verify connectivity | Test with `moq-cli` or the moq.dev web demo tools |
| Add `moq-relay` to CI/deployment docs | Dockerfile or systemd unit file |

**Minimal deployment command:**
```bash
moq-relay \
  --server-bind "[::]:4443" \
  --tls-cert /etc/letsencrypt/live/moq.burrow.chat/fullchain.pem \
  --tls-key /etc/letsencrypt/live/moq.burrow.chat/privkey.pem \
  --auth-public "" \
  --web-http-listen "[::]:8080"
```

**Deliverable:** `moq.burrow.chat` accepting QUIC connections.

---

## Phase 1: Rust MOQ Transport Layer (Weeks 2-3)
*New Rust module wrapping moq-native + hang crates*

### New dependencies (Cargo.toml)
```toml
moq-native = "0.13"
moq-lite = "0.14"
hang = "0.14"
opus = "0.3"          # libopus bindings
openh264 = "0.6"      # H.264 encode/decode (or ffmpeg-next for HW accel)
```

### Tasks
| Task | Details |
|------|---------|
| Add Cargo dependencies | `moq-native`, `moq-lite`, `hang`, `opus`, `openh264` or `ffmpeg-next` |
| Create `rust/src/api/call_moq.rs` | New module — MOQ connection lifecycle, track pub/sub |
| `connect_moq_relay()` | Connect to a MOQ relay URL, return session handle |
| `publish_audio_track()` | Accept raw PCM chunks, Opus-encode, publish via `hang` |
| `publish_video_track()` | Accept raw YUV frames, H.264-encode, publish via `hang` |
| `subscribe_tracks()` | Subscribe to a broadcast path, decode frames, stream back to Dart via `StreamSink` |
| `disconnect_moq()` | Clean shutdown |
| Adapt `call_signaling.rs` | Replace SDP/ICE payloads with MOQ connection info. Keep kinds 25053/25054. Remove kinds 25051/25052 |
| Keep `call_session.rs` | Unchanged — state machine is transport-agnostic |
| Keep `call_quality.rs` | Minor updates to codec preferences |
| Refactor `call_webrtc.rs` → `call_peers.rs` | Keep peer tracking + frame key derivation, remove ICE/SDP/SFU config |
| Regenerate FRB bindings | `flutter_rust_bridge_codegen generate` |

### MOQ Client Pattern (Rust)
```rust
use moq_native::Client;
use moq_lite::Origin;
use hang::{Catalog, CatalogProducer, catalog::*, container::*};

// 1. Create origin and connect
let origin = Origin::new();
let client = Client::new(config)?
    .with_publish(origin.consume())
    .with_consume(origin.produce());
let session = client.connect(relay_url).await?;

// 2. Create broadcast with audio+video tracks
let broadcast = Broadcast::new();
let mut catalog = Catalog::default();
let video_track = catalog.video.create_track("h264", video_config);
let audio_track = catalog.audio.create_track("opus", audio_config);

// 3. Publish encoded frames
let mut video_producer = OrderedProducer::new(video_track.produce());
video_producer.write(Frame {
    timestamp: ts,
    keyframe: true,
    payload: encoded_h264_data.into(),
})?;

// 4. Subscribe to remote participants
let mut announcements = origin_consumer.announced(Some("burrow/<group_id>"));
while let Some((path, broadcast_consumer)) = announcements.next().await {
    // Subscribe to their tracks, decode, send to Flutter
}
```

**Deliverable:** Rust API that can connect to MOQ relay, publish encoded audio/video, and subscribe to remote tracks.

---

## Phase 2: Flutter Media Capture + Render Pipeline (Weeks 3-4)
*Replace flutter_webrtc with direct capture/render*

### New Flutter dependencies (pubspec.yaml)
```yaml
camera: ^0.11.0       # Raw frame capture
record: ^5.0.0        # PCM audio streaming
```

### Tasks
| Task | Details |
|------|---------|
| Replace `webrtc_service.dart` with `moq_media_service.dart` | New service managing capture and playback |
| Camera capture | Use `camera` plugin + `startImageStream()` for raw YUV420 frames |
| Audio capture | Use `record` plugin + `startStream(pcm16)` for raw PCM chunks |
| Send frames to Rust | Via FRB — `Uint8List` (zero-copy) to `publish_audio_track()` / `publish_video_track()` |
| Receive decoded frames from Rust | Via `StreamSink` — Rust decodes and sends RGBA/PCM back to Dart |
| Video rendering (MVP) | Keep `flutter_webrtc` just for `RTCVideoRenderer` (faster to ship) |
| Video rendering (later) | Write minimal platform plugin (~200 lines/platform) for Flutter `Texture` widget |
| Audio playback | Use `cpal` crate in Rust (play decoded PCM directly) or `flutter_soloud` on Dart side |

### Media Pipeline
```
Send:
  camera (YUV420) ──→ FRB (zero-copy) ──→ Rust H.264 encode ──→ MOQ publish
  mic (PCM16)     ──→ FRB (zero-copy) ──→ Rust Opus encode  ──→ MOQ publish

Receive:
  MOQ subscribe ──→ Rust H.264 decode ──→ FRB (RGBA) ──→ Flutter Texture
  MOQ subscribe ──→ Rust Opus decode  ──→ cpal audio output (stays in Rust)
```

**Deliverable:** End-to-end media pipeline: camera → Rust encode → MOQ publish → MOQ subscribe → Rust decode → Flutter render.

---

## Phase 3: Rewire Call Manager + Provider (Weeks 4-5)
*Connect the new transport to the existing UI*

| Task | Details |
|------|---------|
| Rewrite `call_manager.dart` | Replace WebRTC flow with MOQ flow: (1) create session, (2) connect to MOQ relay, (3) publish local tracks, (4) send call event via Nostr, (5) subscribe to remote tracks |
| Adapt `call_provider.dart` | Replace `MediaStream` with MOQ stream abstractions. Keep all state management, timers, control logic |
| Remove `frame_encryption_service.dart` | Frame encryption moves to Rust (encrypt before MOQ publish, decrypt after MOQ subscribe) |
| Keep `nostr_signaling_service.dart` | Unchanged — still bridges Rust signaling stream to Dart |
| Keep all call screens | Only minor video renderer widget changes if needed |
| Keep `main.dart` integration | Overlay pattern unchanged |
| Update `chat_view_screen.dart` | Remove 1:1 restriction from `_startCall()` |

**Deliverable:** 1:1 audio/video calls working end-to-end over MOQ with Nostr signaling.

---

## Phase 4: Multi-Party Group Calls (Weeks 5-6)
*The primary goal of this migration*

| Task | Details |
|------|---------|
| Multi-track subscription | Subscribe to N participants' broadcasts in the same room |
| UI grid layout | Update `in_call_screen.dart` — render grid of video views (2x2, 3x3) with dominant speaker detection |
| Participant join/leave | Handle catalog updates (new broadcast announced = new participant) |
| Group call signaling | Adapt `build_group_call_signaling()` — MLS-encrypted call events with MOQ relay info |
| Relay selection logic | Check group config → caller's kind 10053 → default `moq.burrow.chat` |
| Call controls for groups | Participant list, per-participant mute indicators |
| E2EE for group calls | MLS-derived `exporter_secret` encrypts media frames |

**Deliverable:** Multi-party group calls with any number of participants, E2EE via MLS.

---

## Phase 5: MOQ Relay Discovery via Nostr (Weeks 6-7)
*Publish and discover MOQ relays using Nostr events*

| Task | Details |
|------|---------|
| Create `rust/src/api/moq_relay.rs` | Publish/fetch kind 10053 events |
| `publish_moq_relays()` | Sign and publish relay list to Nostr |
| `fetch_moq_relays()` | Fetch a user's MOQ relay list by pubkey |
| Add MOQ relay config to group settings | Admin can set a group-level MOQ relay |
| Add MOQ relay list to profile settings | User can configure their preferred MOQ relays |
| Relay selection in call flow | Group MOQ relay → caller's kind 10053 → default fallback |

**Deliverable:** Decentralized MOQ relay discovery via Nostr.

---

## Phase 6: Production Hardening (Weeks 7-8)
*Auth, quality, edge cases*

| Task | Details |
|------|---------|
| MOQ relay JWT auth | Build token service: verify Nostr identity (NIP-98) → issue JWT for MOQ relay |
| Echo cancellation | Integrate `webrtc-audio-processing` Rust crate (Google AEC3 standalone) |
| Jitter buffer | Implement in Rust — MOQ's ordered groups simplify this vs RTP |
| A/V lip sync | Timestamp-based sync in decode/render pipeline |
| Network transitions | Handle WiFi ↔ cellular, backgrounding (QUIC handles this well) |
| Bandwidth adaptation | MOQ priority system — drop lower-priority video frames under congestion |
| Remove old WebRTC code | Delete `flutter_webrtc` from pubspec.yaml, remove dead code |

**Deliverable:** Production-quality calling with auth, echo cancellation, and network resilience.

---

## Code Reuse Analysis

### Fully reusable (no changes needed) — ~1,250 lines
- `call_session.rs` (279 lines) — transport-agnostic state machine
- `nostr_signaling_service.dart` (59 lines) — thin Nostr bridge
- `incoming_call_screen.dart` (288 lines) — pure UI
- `outgoing_call_screen.dart` (212 lines) — pure UI
- `chat_view_screen.dart` call sections (~40 lines) — calls callProvider only
- `main.dart` call integration (~35 lines) — Stack overlay pattern

### Mostly reusable (minor adaptations) — ~1,500 lines
- `call_provider.dart` (311 lines) — replace `MediaStream` type
- `call_quality.rs` (443 lines) — update codec names/values
- `in_call_screen.dart` (431 lines) — swap `RTCVideoView` renderer
- `call_signaling.rs` (521 lines) — keep Nostr/NIP-59 infra, replace SDP/ICE payloads
- `call_webrtc.rs` peer tracking + key derivation (~200 lines)

### Must replace — ~860 lines
- `webrtc_service.dart` (276 lines) — entirely WebRTC-coupled
- `frame_encryption_service.dart` (138 lines) — WebRTC FrameCryptor APIs
- `call_manager.dart` core flow (~250 lines) — SDP/ICE logic
- `call_webrtc.rs` ICE/SDP/SFU sections (~200 lines)

### New code — ~1,500-2,000 lines estimated
- `call_moq.rs` — MOQ connection, pub/sub, encode/decode
- `moq_media_service.dart` — Flutter capture/render pipeline
- `moq_relay.rs` — kind 10053 publish/fetch
- Adapted `call_manager.dart` — MOQ flow orchestration

---

## Risk Register

| Risk | Severity | Mitigation |
|------|----------|------------|
| MOQ crates are pre-1.0, API may break | Medium | Pin exact versions, vendor if needed |
| Video encode/decode perf on low-end Android | High | Start with `openh264` (software), add HW accel via `ffmpeg-next` later |
| Echo cancellation quality without libwebrtc | High | `webrtc-audio-processing` crate wraps Google AEC3 standalone |
| QUIC on restrictive networks (UDP blocked) | Medium | moq-relay has WebSocket fallback built in |
| Binary size increase from codec + QUIC deps | Low | Expected ~8-12MB increase, acceptable |
| Flutter `Texture` rendering per-platform plugin | Medium | Well-documented pattern, ~200 lines/platform |

---

## Key Decisions
- **MOQ over WebRTC**: natively supports multi-party via relay fan-out, no TURN/STUN needed
- **Keep Nostr for signaling**: call setup, state updates, relay discovery all stay on Nostr
- **MLS E2EE preserved**: frame encryption keys derived from MLS exporter_secret
- **Caller-picks relay with group override**: simple, Nostr-native relay selection
- **Kind 10053 for MOQ relay lists**: follows NIP-65 / kind 10051 / kind 10063 pattern
- **No SDP/ICE in new flow**: MOQ uses QUIC directly, signaling only carries relay URL + broadcast path

## MOQ Relay Deployment Reference

### Development (local)
```bash
moq-relay --server-bind "[::]:4443" --tls-generate localhost --auth-public ""
```

### Production
```bash
moq-relay \
  --server-bind "[::]:443" \
  --tls-cert /etc/letsencrypt/live/moq.burrow.chat/fullchain.pem \
  --tls-key /etc/letsencrypt/live/moq.burrow.chat/privkey.pem \
  --auth-public "" \
  --web-https-listen "[::]:443" \
  --web-https-cert /etc/letsencrypt/live/moq.burrow.chat/fullchain.pem \
  --web-https-key /etc/letsencrypt/live/moq.burrow.chat/privkey.pem
```

### Ports
| Port | Protocol | Purpose |
|------|----------|---------|
| 443 (UDP) | QUIC/WebTransport | Primary media transport |
| 443 or 8080 (TCP) | HTTP/HTTPS/WebSocket | WebSocket fallback + health API |

### Auth (Phase 6)
- moq-relay uses JWT (JWK/JWKS) with EdDSA, ES256, or HS256
- Nostr uses secp256k1 (not directly compatible)
- Solution: token service that verifies Nostr identity → issues JWT
- Flow: `Client (nsec) → Token Service (NIP-98 verify) → JWT → moq-relay`

### Clustering (future)
- Root + leaf topology
- Leaf nodes connect to root via `--cluster-root`
- Broadcasts auto-discovered across cluster
- Inter-node auth via cluster JWT tokens

## Status
**Saved for later execution** — currently working on other issues.
