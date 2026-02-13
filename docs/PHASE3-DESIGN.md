# Phase 3: Audio & Video Calls — Preliminary Design

## Overview

Burrow Phase 3 adds real-time audio and video calls using WebRTC for media transport and Nostr for signaling. Because Marmot already provides E2EE group infrastructure, we layer call signaling into existing encrypted channels.

---

## WebRTC Signaling over Nostr

### The Problem

WebRTC requires a signaling channel to exchange SDP offers/answers and ICE candidates between peers. Traditionally this is a WebSocket server. Burrow uses Nostr relays instead — no centralized signaling server needed.

### Signaling Protocol

There is no formal NIP for WebRTC signaling yet. This is an **opportunity for Burrow to author one**. Existing prior art:

- **NIP issue #771** — Experimental WebRTC signaling via NIP-04 DMs
- **Nostr Spaces proposal (NIP PR #1092)** — Audio broadcasting via WebRTC + Nostr
- **webConnect.js** — Uses Nostr as one of several signaling transports
- **Nostr Game Engine** — WebRTC signaling over Nostr for multiplayer games

### Proposed Signaling Flow (1:1 Call)

```
Alice                          Nostr Relay                         Bob
  │                                │                                │
  │── kind:25050 call-offer ──────►│───── gift-wrap to Bob ────────►│
  │   (SDP offer, encrypted)       │                                │
  │                                │                                │
  │◄── kind:25051 call-answer ─────│◄──── gift-wrap to Alice ──────│
  │   (SDP answer, encrypted)      │                                │
  │                                │                                │
  │── kind:25052 ice-candidate ───►│───── gift-wrap to Bob ────────►│
  │◄── kind:25052 ice-candidate ───│◄──── gift-wrap to Alice ──────│
  │   (repeat for each candidate)  │                                │
  │                                │                                │
  ╔════════════════════════════════════════════════════════════════╗
  ║           WebRTC P2P connection established                    ║
  ║           (DTLS-SRTP encrypted media flows directly)           ║
  ╚════════════════════════════════════════════════════════════════╝
```

### Proposed Event Kinds

| Kind | Name | Description |
|------|------|-------------|
| 25050 | call-offer | SDP offer + call metadata (audio/video, group ID) |
| 25051 | call-answer | SDP answer |
| 25052 | ice-candidate | ICE candidate exchange |
| 25053 | call-hangup | End call signal |
| 25054 | call-reject | Decline incoming call |
| 25055 | call-busy | Busy signal |

All signaling events are **gift-wrapped** (NIP-59) for metadata protection. They're ephemeral — relays can delete them after delivery (short TTL).

### For Marmot Groups (Group Calls)

For group calls, signaling messages are sent as **Marmot group messages** (MLS-encrypted) rather than gift-wrapped DMs. This means:

- Only group members can see call signaling
- Existing E2EE infrastructure handles encryption
- No new key management needed

---

## Encryption Considerations

### Layers of Encryption

1. **Signaling:** Gift-wrapped Nostr events (1:1) or Marmot MLS messages (group)
2. **Media transport:** DTLS-SRTP (WebRTC's built-in encryption)
3. **Optional: Insertable Streams** — Additional E2EE layer for group calls via SFU

### Why WebRTC's SRTP Is Sufficient for 1:1

For peer-to-peer calls, DTLS-SRTP provides E2EE directly between the two peers. No TURN relay can decrypt the media (TURN only relays encrypted packets).

### Group Calls and SFU

For group calls with 5+ participants, a mesh topology is impractical. Options:

1. **Full mesh (2-5 participants):** Each peer connects to every other. Simple, truly E2EE, but O(n²) connections.

2. **SFU with Insertable Streams (5+ participants):** A Selective Forwarding Unit routes packets but can't decrypt them. WebRTC's Insertable Streams API allows encrypting media frames with MLS-derived keys before SRTP.

```
┌───────┐     ┌───────┐     ┌───────┐
│ Alice │     │  Bob  │     │ Carol │
└───┬───┘     └───┬───┘     └───┬───┘
    │             │             │
    │   E2EE      │   E2EE      │   E2EE
    │  frames     │  frames     │  frames
    │             │             │
    └─────────┐   │   ┌─────────┘
              ▼   ▼   ▼
          ┌───────────────┐
          │   SFU Server  │
          │ (can't decrypt│
          │   media)      │
          └───────────────┘
```

The MLS group ratchet (already managed by Marmot) provides the shared secret for encrypting media frames. This is a natural extension of the existing protocol.

---

## Group Call Architecture

### Mesh Mode (Default, ≤5 Participants)

- Direct peer-to-peer connections between all participants
- Each participant sends their media to every other participant
- True E2EE — no intermediary can decrypt
- Announced via Marmot group message: "Alice started a call"

### SFU Mode (6+ Participants)

- Burrow-operated or self-hosted SFU (e.g., Janus, mediasoup, LiveKit)
- Insertable Streams for frame-level encryption using MLS keys
- SFU only sees encrypted frames — can route but not decrypt
- Optional: community can run their own SFUs

### Call State Machine

```
IDLE ──► RINGING ──► CONNECTING ──► CONNECTED ──► ENDED
  │         │            │              │
  │         ▼            ▼              ▼
  │      REJECTED     FAILED        HANGUP
  │         │
  ▼         ▼
 BUSY    TIMEOUT
```

---

## STUN/TURN Infrastructure

- **STUN:** Use public STUN servers (Google, Twilio) for NAT traversal discovery
- **TURN:** Self-hosted TURN servers for relay fallback when P2P fails
  - `coturn` is the standard open-source TURN server
  - Deployed in multiple regions for low latency
  - Credential rotation via short-lived tokens
- **Future:** Explore Nostr relay operators also running TURN as a service

---

## Flutter Implementation

### Dependencies
```yaml
dependencies:
  flutter_webrtc: ^latest      # WebRTC for Flutter
  # Signaling handled via existing Rust/Nostr bridge
```

### Key Components

- **CallManager (Rust):** Manages call state, generates/parses SDP, handles ICE
- **CallUI (Flutter):** Incoming call screen, in-call controls, video rendering
- **SignalingBridge:** Sends/receives call events via Marmot/Nostr
- **MediaControls:** Mute, camera toggle, speaker selection, screen share

### UI Screens

- **Incoming call:** Full-screen with caller info, accept/reject buttons
- **In-call (audio):** Minimal UI — timer, mute, speaker, hangup
- **In-call (video):** Video feeds + floating self-view + controls overlay
- **Group call:** Grid layout for video, list for audio-only participants

---

## NIP Authorship Opportunity

No formal NIP exists for WebRTC signaling on Nostr. Burrow should author one:

- **NIP-XX: WebRTC Signaling** — Event kinds, flow, gift-wrapping requirements
- Co-author with Derek (Nostr DevRel) and submit to `nostr-protocol/nips`
- Reference existing implementations (NIP #771, Nostr Spaces, webConnect.js)
- This positions Burrow as the standard for Nostr calling

---

## Refined Architecture (Post-Research)

> Updated 2026-02-12 after comprehensive research. See `PHASE3-RESEARCH.md` for full findings.

### Key Decisions

1. **SFU: LiveKit** — Apache 2.0, Go-based, first-class Flutter SDK (`livekit_client`), built-in E2EE support, self-hostable. LiveKit sponsors flutter_webrtc, so the stack is aligned.

2. **Hybrid Topology:**
   - 2 peers: P2P (DTLS-SRTP, zero infrastructure)
   - 3-4 peers: Full mesh (DTLS-SRTP, zero infrastructure)
   - 5+ peers: LiveKit SFU with frame-level encryption (MLS-derived keys)

3. **E2EE for SFU Mode:** Derive media encryption keys from MLS `exporter_secret`:
   ```
   media_key = MLS.export_secret("burrow-media-v1", call_id, 32)
   ```
   Applied via flutter_webrtc's `FrameCryptor` API (AES-128-GCM). SFU forwards opaque encrypted frames.

4. **NIP Authorship:** Kinds 25050-25059 for call signaling. No existing NIP covers this — Burrow defines the standard. All events gift-wrapped (NIP-59) with NIP-40 expiration tags.

5. **WhiteNoise Interop:** WhiteNoise has no call features. Our design should allow any Marmot client to adopt calls later. Coordinate `exporter_secret` label conventions.

6. **STUN/TURN:** Public STUN (Google), self-hosted coturn for TURN. Short-lived HMAC credentials per call.

7. **Native Call Integration:** CallKit (iOS) + ConnectionService (Android) for lock-screen answering, audio routing, system call log.

### Dependencies

```yaml
dependencies:
  flutter_webrtc: ^0.12.7        # P2P WebRTC
  livekit_client: ^latest         # SFU mode (wraps flutter_webrtc)
  # Signaling via existing Rust/Marmot bridge
```

### Implementation Order

1. **Phase 3a:** 1:1 audio calls (P2P, gift-wrapped signaling)
2. **Phase 3b:** 1:1 video calls (camera UI, bandwidth adaptation)
3. **Phase 3c:** Group calls — mesh mode (≤4 participants)
4. **Phase 3d:** Group calls — SFU mode (LiveKit, frame encryption)
5. **Phase 3e:** Native call integration (CallKit/ConnectionService)
6. **Phase 3f:** NIP submission and interop testing

## Open Questions (Resolved + Remaining)

| Question | Resolution |
|----------|-----------|
| SFU hosting | LiveKit self-hosted initially; LiveKit Cloud as fallback |
| TURN costs | Self-hosted coturn; future: Lightning micropayments |
| Call history | Local-only storage (call log in SQLite), not on Nostr |
| Interoperability | Yes — NIP-XX defines open standard for any Nostr client |
| WhiteNoise coordination | Their Rust crate is messaging-only; calls are new territory |

### Remaining Open Questions

1. **LiveKit room provisioning** — Who creates rooms? Caller's device? Dedicated provisioner?
2. **TURN region expansion** — When to add more regions? Usage-based?
3. **Screen sharing** — Phase 3 scope or Phase 4?
4. **Recording** — Should we support call recording? Privacy implications?
