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

## Open Questions

1. **SFU hosting** — Who runs it? Community-operated? Paid tier?
2. **TURN costs** — Relay bandwidth isn't free. Lightning micropayments for TURN?
3. **Call history** — Store call metadata (duration, participants) in Marmot group or local only?
4. **Interoperability** — Should other Nostr clients be able to call Burrow users? (Yes, if we author a NIP)
