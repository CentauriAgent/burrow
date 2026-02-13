# Phase 3 Research: WebRTC + Nostr Signaling Architecture

> Research completed: 2026-02-12
> Author: Centauri (architect agent)

---

## Table of Contents

1. [flutter_webrtc Plugin](#1-flutter_webrtc-plugin)
2. [Existing Nostr + WebRTC Implementations](#2-existing-nostr--webrtc-implementations)
3. [NIP-59 Gift Wrapping for Signaling Privacy](#3-nip-59-gift-wrapping-for-signaling-privacy)
4. [Group Call Topology: Mesh vs SFU vs Hybrid](#4-group-call-topology)
5. [E2EE for Calls](#5-e2ee-for-calls)
6. [SFU Options Comparison](#6-sfu-options-comparison)
7. [WhiteNoise Analysis](#7-whitenoise-analysis)
8. [Recommended Architecture](#8-recommended-architecture)
9. [NIP Draft Outline](#9-nip-draft-outline)
10. [Platform Considerations](#10-platform-considerations)

---

## 1. flutter_webrtc Plugin

### Overview

**Package:** `flutter_webrtc` (pub.dev)
**Version:** 0.12.7+ (Jan 2025)
**Maintainer:** CloudWebRTC / flutter-webrtc org
**Sponsor:** LiveKit is a listed sponsor

### Platform Support Matrix

| Feature | Android | iOS | Web | macOS | Windows | Linux |
|---------|---------|-----|-----|-------|---------|-------|
| Audio/Video | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Data Channel | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Screen Capture | ✅ | ✅* | ✅ | ✅ | ✅ | ✅ |
| Unified-Plan | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Simulcast | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| E2EE | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Insertable Streams | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

*iOS screen capture requires broadcast extension setup.

### Key API Patterns

```dart
// Create peer connection
final config = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'turn:turn.burrow.chat:3478', 'username': 'user', 'credential': 'pass'},
  ]
};
RTCPeerConnection pc = await createPeerConnection(config);

// Get local media
MediaStream localStream = await navigator.mediaDevices.getUserMedia({
  'audio': true,
  'video': {'facingMode': 'user'},
});

// Add tracks
localStream.getTracks().forEach((track) {
  pc.addTrack(track, localStream);
});

// Create offer
RTCSessionDescription offer = await pc.createOffer();
await pc.setLocalDescription(offer);
// → Send offer.sdp via Nostr signaling

// Handle ICE candidates
pc.onIceCandidate = (RTCIceCandidate candidate) {
  // → Send candidate via Nostr signaling
};

// Receive remote stream
pc.onTrack = (RTCTrackEvent event) {
  remoteStream = event.streams[0];
  // → Render in RTCVideoRenderer
};

// Video rendering
RTCVideoRenderer renderer = RTCVideoRenderer();
await renderer.initialize();
renderer.srcObject = remoteStream;
// Use RTCVideoView(renderer) in widget tree
```

### E2EE / Insertable Streams Support

flutter_webrtc supports E2EE natively on all platforms. The `FrameCryptor` API allows frame-level encryption:

```dart
// Create frame cryptor for a sender
final frameCryptor = await pc.createFrameCryptorForSender(
  sender: sender,
  algorithm: Algorithm.kAesGcm,
  keyProvider: keyProvider,
);
await frameCryptor.setEnabled(true);
```

This is critical for SFU mode where the SFU forwards encrypted frames it cannot decrypt.

### Implications for Burrow

- **Excellent cross-platform support** — covers all our target platforms
- **Built-in E2EE support** — no need for custom insertable streams implementation
- **LiveKit sponsorship** — natural path to LiveKit SFU if needed
- **Active maintenance** — regular releases through 2025
- **Unified-Plan** — modern WebRTC, no legacy Plan B issues

---

## 2. Existing Nostr + WebRTC Implementations

### NIP Issue #771: WebRTC Signaling (Sep 2023)

- **Author:** stefanha
- **Approach:** Used NIP-04 encrypted DMs for WebRTC signaling
- **Implementation:** 2-player tic-tac-toe game, HTML/JS
- **Key findings:**
  - Works! WebRTC connections can be established via Nostr relays
  - Ephemeral kinds should be used (signaling messages are transient)
  - Some relays reject unknown ephemeral kinds — relay support needed
  - Relay latency can cause WebRTC connection timeout
- **Status:** Experiment only, no NIP proposed

### NIP PR #1092: Nostr Spaces Protocol (Audio Broadcasting)

- **Author:** iicuriosity
- **Approach:** Real-time P2P audio broadcasting via WebRTC + Nostr signaling
- **Focus:** Twitter/X Spaces equivalent for Nostr
- **Status:** Draft PR, JavaScript implementation started
- **Relevance:** Different use case (public broadcasting vs private calls) but shares signaling patterns

### webConnect.js

- Uses Nostr as one of several possible signaling transports
- General-purpose WebRTC connection library
- Not Nostr-specific

### Key Takeaways

- **No formal NIP exists** for WebRTC call signaling — this is a greenfield opportunity
- **NIP-04 is deprecated** — we should use NIP-59 gift wrapping (NIP-44 encryption)
- **Ephemeral events are essential** — signaling data is useless after connection establishment
- **Relay latency is a real concern** — need ICE trickle and aggressive timeouts
- **Burrow can define the standard** by authoring the NIP

---

## 3. NIP-59 Gift Wrapping for Signaling Privacy

### How NIP-59 Works

NIP-59 defines a two-layer encryption scheme:

1. **Seal (kind 13):** Inner event signed by the real author, encrypted to recipient using NIP-44
2. **Gift Wrap (kind 1059):** Outer event signed by a random disposable key, contains the encrypted seal

This provides:
- **Sender anonymity:** The outer event is signed by a throwaway key
- **Content privacy:** Double-encrypted (seal + wrap)
- **Metadata protection:** Relays cannot correlate sender/receiver from the outer event
- **Timestamp obfuscation:** Outer timestamp can be randomized

### Application to Call Signaling

For 1:1 call signaling, each message (offer, answer, ICE candidate, hangup) is gift-wrapped:

```
Inner event (kind 25050 call-offer):
{
  "kind": 25050,
  "pubkey": "<caller's real pubkey>",
  "content": "<SDP offer JSON>",
  "tags": [
    ["p", "<callee pubkey>"],
    ["call-id", "<unique call identifier>"],
    ["call-type", "audio|video"]
  ],
  "created_at": <real timestamp>
}
↓ Sealed with NIP-44 to recipient
↓ Wrapped in kind 1059 with random key
```

### Why Gift Wrap for Signaling

- **Privacy:** Relays can't see who is calling whom
- **No new infrastructure:** Reuses existing NIP-59 support in relays
- **Ephemeral by nature:** Gift wraps can have short TTLs; relays already expect to garbage-collect them
- **Consistent with NIP-17:** Private DMs already use gift wrapping — call signaling is the same pattern

### For Group Calls

Group call signaling does NOT use gift wrapping. Instead, it goes through **Marmot MLS-encrypted group messages**:
- Already encrypted to all group members
- Already has metadata protection via Marmot protocol
- More efficient (one message to group vs N gift wraps)

---

## 4. Group Call Topology

### Mesh (≤4 participants)

```
     A ←——→ B
     ↕ ╲  ╱ ↕
     ↕  ╲╱  ↕
     ↕  ╱╲  ↕
     ↕ ╱  ╲ ↕
     C ←——→ D
```

- **Connections:** n(n-1)/2 — 4 peers = 6 connections
- **Upload:** Each peer sends n-1 streams
- **True E2EE:** No intermediary, DTLS-SRTP between each pair
- **Pros:** Zero infrastructure, maximum privacy, simple
- **Cons:** Bandwidth scales O(n²), impractical above ~4 peers on mobile

### SFU (5+ participants)

```
     A ──→ SFU ──→ B
     B ──→ SFU ──→ A
     C ──→ SFU ──→ A, B
     ...
```

- **Connections:** Each peer has 1 upload + 1 download connection to SFU
- **Upload:** Each peer sends 1 stream
- **E2EE:** Requires Insertable Streams / frame-level encryption
- **Pros:** Bandwidth scales O(n), supports large groups
- **Cons:** Requires SFU infrastructure, more complex E2EE

### Recommended: Hybrid Approach

| Participants | Topology | E2EE Method |
|-------------|----------|-------------|
| 2 | P2P | DTLS-SRTP (built-in) |
| 3-4 | Mesh | DTLS-SRTP (built-in) |
| 5+ | SFU | Frame encryption via MLS-derived keys |

**Automatic escalation:** Start with mesh, offer SFU upgrade when participant count exceeds threshold. The threshold is configurable (default: 5) and can be adjusted based on device capability detection.

---

## 5. E2EE for Calls

### 1:1 and Small Mesh (≤4)

Standard WebRTC DTLS-SRTP is sufficient:
- Keys negotiated directly between peers via DTLS handshake
- No intermediary can decrypt
- TURN relays only forward encrypted packets
- **No additional work needed** — this is WebRTC's default behavior

### SFU Mode: Frame-Level Encryption with MLS Keys

When using an SFU, DTLS-SRTP terminates at the SFU (the SFU must decrypt SRTP to route). To maintain E2EE, we add frame-level encryption using **Insertable Streams**.

#### Key Derivation from MLS

Marmot already manages MLS group state. We derive media encryption keys from MLS:

```
media_key = MLS.export_secret("burrow-media-v1", call_id, 32)
```

The MLS `exporter_secret` (RFC 9420 §8) allows deriving application-specific keys from the group's shared secret. This means:
- **No new key exchange** — keys come from existing MLS group state
- **Forward secrecy** — when MLS epoch advances, media keys rotate
- **Post-compromise security** — compromised keys don't affect future epochs
- **Group membership enforcement** — only MLS group members have the key

#### Encryption Flow

```
Raw frame → AES-128-GCM encrypt (media_key) → Encrypted frame → SRTP → SFU → SRTP → Encrypted frame → AES-128-GCM decrypt → Raw frame
```

The SFU receives SRTP packets containing encrypted frames. It can route them (inspect RTP headers) but cannot decrypt the frame payload.

#### flutter_webrtc FrameCryptor Integration

```dart
// Derive key from MLS exporter_secret
final mediaKey = marmotGroup.exportSecret("burrow-media-v1", callId, 32);

// Set up frame encryption
final keyProvider = await FrameCryptorFactory.createDefaultKeyProvider(
  KeyProviderOptions(sharedKey: true, ratchetSalt: callIdBytes),
);
await keyProvider.setSharedKey(key: mediaKey);

// Apply to each sender
for (final sender in pc.senders) {
  final cryptor = await FrameCryptorFactory.createFrameCryptorForRtpSender(
    sender: sender,
    algorithm: Algorithm.kAesGcm,
    keyProvider: keyProvider,
  );
  await cryptor.setEnabled(true);
}
```

#### Key Rotation

When MLS epoch changes (member join/leave/update):
1. New `media_key` derived from new epoch's `exporter_secret`
2. `keyProvider.setSharedKey(key: newMediaKey)` on all participants
3. Short overlap period where both old and new keys are accepted (ratchet window)

---

## 6. SFU Options Comparison

### LiveKit (Recommended)

- **Language:** Go (Pion WebRTC)
- **License:** Apache 2.0
- **Flutter SDK:** `livekit_client` — first-class, well-maintained
- **E2EE:** Built-in support, uses same flutter_webrtc FrameCryptor under the hood
- **Scaling:** Horizontally scalable, multi-node with Redis
- **Self-hosted:** Single binary, Docker, Kubernetes helm chart
- **Cloud:** LiveKit Cloud available for managed hosting
- **Features:** Simulcast, adaptive bitrate, recording, egress/ingress
- **Community:** Very active, 22k+ GitHub stars

**Why LiveKit for Burrow:**
- Best Flutter support of any SFU
- E2EE is a first-class feature — aligns with our requirements
- Self-hostable (decentralization ethos) but cloud option available
- Active development and sponsor of flutter_webrtc
- The `livekit_client` Flutter SDK wraps flutter_webrtc, so we can use raw flutter_webrtc for P2P and livekit_client for SFU — same underlying engine

### Janus

- **Language:** C
- **License:** GPL-3.0
- **Flutter SDK:** None official (community wrappers exist)
- **E2EE:** Insertable Streams support via Janus plugin
- **Scaling:** Complex (multi-instance requires external coordination)
- **Pros:** Mature, plugin architecture, SIP gateway
- **Cons:** No official Flutter SDK, GPL license, complex deployment

### mediasoup

- **Language:** C++/Node.js
- **License:** ISC
- **Flutter SDK:** None (community `flutter_mediasoup` exists but unmaintained)
- **E2EE:** Possible but not built-in
- **Pros:** High performance, flexible
- **Cons:** No Flutter SDK, requires Node.js server

### Decision: LiveKit

LiveKit is the clear winner for Burrow:
1. Best Flutter ecosystem support
2. Built-in E2EE aligned with our architecture
3. Self-hostable (Apache 2.0)
4. Sponsors flutter_webrtc — aligned incentives
5. Single Go binary — easy deployment

---

## 7. WhiteNoise Analysis

### Current State

WhiteNoise (by Jeff Gardner / Parres HQ) is the only other known app implementing Marmot protocol:
- **Rust core:** `whitenoise-rs` crate (Marmot + MLS on Nostr)
- **Flutter frontend:** Separate repo
- **Status:** Alpha (v0.1.0-alpha.3 as of Feb 2025)
- **License:** AGPL-3.0

### Call Features

**WhiteNoise has NO audio/video call features.** It is purely a messaging app:
- 1:1 encrypted DMs
- MLS group chats
- No WebRTC, no media, no call signaling

### Implications for Burrow

- **No competition** on calls — Burrow will be first Marmot-protocol app with calls
- **Interoperability consideration:** Our call signaling NIP should be designed so WhiteNoise (or any Marmot client) could adopt it later
- **MLS key derivation:** We should coordinate with WhiteNoise team on the `exporter_secret` label convention to avoid conflicts
- **Shared Rust crate:** Both apps use `whitenoise-rs`; our call extensions could potentially be contributed upstream

---

## 8. Recommended Architecture

### Overview

```
┌─────────────────────────────────────────────────┐
│                   Burrow App                     │
│                                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐ │
│  │ Call UI   │  │ Chat UI  │  │ Settings UI   │ │
│  │ (Flutter) │  │ (Flutter)│  │ (Flutter)     │ │
│  └────┬─────┘  └────┬─────┘  └───────────────┘ │
│       │              │                           │
│  ┌────┴──────────────┴───────────────────────┐  │
│  │           Flutter ↔ Rust Bridge           │  │
│  │           (flutter_rust_bridge)            │  │
│  └────┬──────────────┬───────────────────────┘  │
│       │              │                           │
│  ┌────┴─────┐  ┌─────┴──────┐                  │
│  │CallEngine│  │  Marmot    │                   │
│  │ (Rust)   │  │  (Rust)    │                   │
│  │          │  │            │                   │
│  │ - WebRTC │◄─┤ - MLS      │                   │
│  │   control│  │ - Groups   │                   │
│  │ - SDP gen│  │ - Keys     │                   │
│  │ - ICE    │  │ - Messages │                   │
│  │ - State  │  │            │                   │
│  └────┬─────┘  └─────┬──────┘                  │
│       │              │                           │
│       ▼              ▼                           │
│  flutter_webrtc   Nostr Relays                  │
│  (native WebRTC)  (transport)                    │
└─────────────────────────────────────────────────┘
```

### Signaling Flow (1:1 Call)

1. **Caller** creates WebRTC offer via flutter_webrtc
2. **CallEngine (Rust)** wraps offer in kind 25050 event
3. **Marmot** gift-wraps (NIP-59) and publishes to callee's relays
4. **Callee** receives, unwraps, presents incoming call UI
5. **Callee** accepts → creates answer → gift-wraps kind 25051 back
6. ICE candidates exchanged via kind 25052 (gift-wrapped)
7. P2P connection established → media flows directly

### Signaling Flow (Group Call)

1. **Initiator** sends "call started" as Marmot group message
2. Each joiner sends their SDP offer as Marmot group message (MLS-encrypted)
3. If ≤4 participants: full mesh, each pair exchanges SDP directly
4. If 5+: initiator provisions a LiveKit room, shares room token via Marmot message
5. Participants join LiveKit with frame encryption enabled (MLS-derived key)

### STUN/TURN Strategy

- **STUN:** Google public STUN servers (free, reliable)
- **TURN:** Self-hosted coturn instances
  - Short-lived credentials (HMAC-based, rotated per call)
  - Initially: 1-2 regions (US, EU)
  - Future: Lightning micropayments for TURN relay bandwidth

---

## 9. NIP Draft Outline

### NIP-XX: WebRTC Call Signaling

#### Abstract

Defines event kinds and flows for establishing WebRTC audio/video calls between Nostr users, using gift-wrapped events for privacy-preserving signaling.

#### Event Kinds

| Kind | Name | Content | Required Tags |
|------|------|---------|--------------|
| 25050 | `call-offer` | SDP offer (JSON) | `p`, `call-id`, `call-type` |
| 25051 | `call-answer` | SDP answer (JSON) | `p`, `call-id` |
| 25052 | `ice-candidate` | ICE candidate (JSON) | `p`, `call-id` |
| 25053 | `call-hangup` | Optional reason | `p`, `call-id` |
| 25054 | `call-reject` | Optional reason | `p`, `call-id` |
| 25055 | `call-busy` | Empty | `p`, `call-id` |
| 25056 | `call-ringing` | Empty | `p`, `call-id` |

**Kind range 25050-25059** — ephemeral replaceable range for call signaling.

#### Tag Definitions

```json
{
  "tags": [
    ["p", "<recipient pubkey>"],
    ["call-id", "<unique UUIDv4>"],
    ["call-type", "audio|video"],
    ["expiration", "<unix timestamp, +60s>"]
  ]
}
```

#### Privacy Requirements

- All signaling events MUST be gift-wrapped (NIP-59)
- Relays SHOULD treat these as ephemeral (delete after delivery or short TTL)
- Clients MUST generate a new `call-id` for each call attempt
- The `expiration` tag (NIP-40) signals when relays can discard the event

#### Flow Diagram

```
Caller                     Relay                      Callee
  │                          │                           │
  │ kind:1059 (wraps 25050) ►│                           │
  │     call-offer + SDP     │── deliver ──────────────►│
  │                          │                           │
  │                          │◄── kind:1059 (wraps 25056)│
  │◄── deliver ──────────────│     call-ringing          │
  │                          │                           │
  │                          │◄── kind:1059 (wraps 25051)│
  │◄── deliver ──────────────│     call-answer + SDP     │
  │                          │                           │
  │ kind:1059 (wraps 25052) ►│                           │
  │     ICE candidate        │── deliver ──────────────►│
  │                          │                           │
  │                          │◄── kind:1059 (wraps 25052)│
  │◄── deliver ──────────────│     ICE candidate         │
  │                          │                           │
  ╔═══════════════════════════════════════════════════════╗
  ║        P2P WebRTC connection established              ║
  ╚═══════════════════════════════════════════════════════╝
```

#### Group Call Extension

For Marmot/MLS group calls, signaling events are sent as group messages instead of gift wraps. The same event kinds are used, but:
- Content is MLS-encrypted (not gift-wrapped)
- The `p` tag is replaced by the group identifier
- A `call-join` (kind 25057) event is added for members joining an active call

#### STUN/TURN Discovery

Clients MAY publish their preferred STUN/TURN servers in a kind 10050-like relay list, or use well-known defaults. TURN credentials should be short-lived.

---

## 10. Platform Considerations

### Mobile (iOS/Android)

- **Battery:** WebRTC is power-hungry. Implement aggressive bitrate adaptation.
  - Audio-only calls should disable video processing entirely
  - Background calls: reduce to audio-only, lower codec complexity
- **Bandwidth:** Mobile networks are variable
  - Simulcast (send multiple quality layers) — SFU selects appropriate layer per receiver
  - Adaptive bitrate estimation (built into WebRTC)
- **Background execution:**
  - iOS: VoIP push notifications (PushKit) to wake app for incoming calls
  - Android: Foreground service with persistent notification during calls
- **Permissions:** Camera + microphone require runtime permissions on both platforms
- **CallKit (iOS) / ConnectionService (Android):** Integrate with native call UI for:
  - Lock screen call answering
  - System call log integration
  - Audio routing (speaker, bluetooth, earpiece)

### Desktop (macOS/Windows/Linux)

- Fewer constraints — more bandwidth, power, screen space
- Screen sharing support built into flutter_webrtc
- Multiple monitor support for video feeds

### Web

- Full flutter_webrtc support
- E2EE requires Web Workers for frame encryption (livekit handles this)
- No background execution — call ends when tab closes

### Bandwidth Estimates

| Mode | Upload | Download (4 peers) |
|------|--------|-------------------|
| Audio only (Opus) | 32 kbps | 96 kbps |
| Video 360p | 500 kbps | 1.5 Mbps |
| Video 720p | 1.5 Mbps | 4.5 Mbps |
| SFU video 720p | 1.5 Mbps | 4.5 Mbps (same) |

Mesh upload scales with peers; SFU upload is constant.

---

## Summary of Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| WebRTC library | flutter_webrtc | Best cross-platform support, E2EE built-in |
| 1:1 signaling | Gift-wrapped ephemeral events (NIP-59) | Privacy, no new infrastructure |
| Group signaling | Marmot MLS group messages | Already encrypted, natural fit |
| Small group topology | Full mesh (≤4) | True E2EE, zero infrastructure |
| Large group topology | LiveKit SFU (5+) | Scalable, Flutter SDK, E2EE support |
| SFU choice | LiveKit | Apache 2.0, Go, Flutter SDK, self-hostable |
| Media E2EE (SFU) | Frame encryption via MLS exporter_secret | Reuses existing key management |
| NIP authorship | Yes — kinds 25050-25059 | Greenfield opportunity, positions Burrow as standard |
| TURN | Self-hosted coturn | Decentralized, low cost |
