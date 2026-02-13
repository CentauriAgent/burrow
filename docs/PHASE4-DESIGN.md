# Phase 4: AI Meeting Assistant — Preliminary Design

## Overview

Burrow Phase 4 adds an AI agent that joins calls as a participant, transcribes in real-time, identifies speakers, extracts action items, and delivers post-call summaries — all within the existing E2EE Marmot infrastructure. Think Otter.ai but decentralized, private, and agent-native.

---

## How the Agent Joins Calls

### Agent as Group Member

The AI agent has its own Nostr keypair and is a regular Marmot group member. This means:

- Agent receives group messages (including call signaling)
- Agent can be invited/removed like any member
- Agent participates in MLS key ratcheting
- Agent's identity is transparent — everyone knows it's a bot

### Call Participation Flow

```
1. Human starts a group call (Phase 3 signaling)
2. Agent receives call-offer via Marmot group message
3. Agent joins as audio-only WebRTC peer (no video, no camera)
4. Agent receives mixed audio stream
5. Agent pipes audio to transcription engine
6. Agent sends real-time transcript snippets to group chat (optional)
7. On call end, agent generates summary and posts to group
```

### Agent Runtime

The agent runs as a headless service (no Flutter UI needed):

```
┌─────────────────────────────────────────┐
│           Burrow Agent Service          │
│                                         │
│  ┌───────────┐  ┌────────────────────┐  │
│  │  Marmot   │  │   WebRTC Client    │  │
│  │  Client   │  │  (audio-only)      │  │
│  │  (Rust)   │  │  (libwebrtc/GStreamer)│ │
│  └─────┬─────┘  └────────┬───────────┘  │
│        │                 │              │
│        │     Audio Stream│              │
│        │                 ▼              │
│        │        ┌────────────────┐      │
│        │        │  Transcription │      │
│        │        │  Engine        │      │
│        │        │  (Whisper/     │      │
│        │        │   Deepgram)    │      │
│        │        └───────┬────────┘      │
│        │                │               │
│        │                ▼               │
│        │       ┌─────────────────┐      │
│        │       │  LLM Pipeline   │      │
│        │       │  (Summary /     │      │
│        │       │   Action Items) │      │
│        │       └───────┬─────────┘      │
│        │               │                │
│        ◄───────────────┘                │
│        │  Post results as               │
│        │  group messages                │
│        ▼                                │
│   Nostr Relays                          │
└─────────────────────────────────────────┘
```

---

## Transcription Pipeline

### Option A: Local Whisper (Privacy-First, Recommended Default)

- **Model:** OpenAI Whisper (large-v3) or `faster-whisper` (CTranslate2 optimized)
- **Runtime:** Local GPU (CUDA/Metal) or CPU fallback
- **Latency:** ~2-5 seconds for real-time with chunked processing
- **Languages:** 99 languages with auto-detection
- **Accuracy:** 95%+ with medium+ models

**Architecture:**
```
Audio chunks (30s segments with overlap)
    │
    ▼
faster-whisper (GPU)
    │
    ▼
Raw transcript with timestamps
    │
    ▼
WhisperX (alignment + diarization)
    │
    ▼
Speaker-labeled transcript
```

### Option B: Cloud API (Lower Latency, Less Private)

- **Deepgram:** Real-time streaming transcription, excellent accuracy, speaker diarization built-in
- **AssemblyAI:** Real-time, good diarization, action item detection
- **Trade-off:** Audio leaves the device (breaks E2EE promise for transcription)

### Recommended: User Choice

Let users choose:
- **Local mode:** All transcription on-device/on-server. True privacy. Needs GPU.
- **Cloud mode:** Faster, cheaper, but audio goes to API provider. Opt-in only.

---

## Speaker Diarization

Identifying who said what:

### Approaches

1. **WhisperX** — Post-processes Whisper output with pyannote.audio for speaker segmentation
2. **NeMo MSDD** — NVIDIA's multi-scale diarization decoder
3. **WebRTC-native:** Since each participant has a separate audio stream (before mixing), the agent can tag speakers by stream ID → Nostr identity mapping

**Best approach for Burrow:** Use WebRTC's per-participant audio tracks. Each track maps to a known Nostr pubkey. No ML diarization needed for group calls — we know exactly who's speaking from the transport layer.

For mixed audio (e.g., recording a physical meeting), fall back to WhisperX diarization.

---

## Post-Call Processing

### Summary Generation

After the call ends, the agent processes the full transcript:

```
Full transcript (with speaker labels + timestamps)
    │
    ▼
LLM (Claude / Ollama local)
    │
    ├──► Executive Summary (2-3 paragraphs)
    ├──► Key Discussion Points (bulleted)
    ├──► Action Items (who, what, deadline)
    ├──► Decisions Made
    └──► Open Questions
```

### Action Item Extraction

The LLM identifies action items with structured output:

```json
{
  "action_items": [
    {
      "assignee": "npub1abc...",
      "assignee_name": "Derek",
      "description": "Review the Phase 2 design doc",
      "deadline": "2026-02-20",
      "priority": "high"
    }
  ]
}
```

Action items are posted as a structured Marmot group message that Burrow clients can render as a checklist.

### Delivery

All outputs are delivered as **Marmot group messages** — encrypted, decentralized, available to all group members:

1. **Immediate (during call):** Live transcript snippets (optional, configurable)
2. **Post-call (within 2 minutes):** Full summary + action items
3. **Persistent:** Searchable transcript stored locally by each client

---

## Live Features (During Call)

### Real-Time Transcript Display
- Agent sends transcript chunks as group messages with special tags
- Burrow app renders them in a dedicated "transcript" panel
- Scrolling, searchable, with speaker labels

### Live Q&A
- Participants can type questions to the agent during the call
- "Hey Burrow, what did we decide about the timeline?"
- Agent searches recent transcript context and responds

### Smart Alerts
- Agent detects when someone says "action item" or "TODO" and highlights it
- Agent notices when a topic changes and adds section headers

---

## Privacy Architecture

### E2EE Preservation

- Agent is an MLS group member — it has access to decrypted messages by design
- Transcription happens on the agent's runtime (local or cloud, user's choice)
- Summaries are encrypted via Marmot before delivery
- No data leaves the Marmot group unless user explicitly exports

### Trust Model

- Users explicitly invite the agent to a group (opt-in)
- Agent's Nostr pubkey is visible to all members
- Agent can be removed at any time (standard MLS member removal)
- Local Whisper mode: audio never leaves the user's infrastructure

### Data Retention

- Transcripts stored locally by each client (not on relays)
- Configurable retention: auto-delete after N days
- Export: users can export transcripts as markdown/PDF

---

## Tech Stack

| Component | Technology | Notes |
|-----------|-----------|-------|
| Agent runtime | Rust + Tokio | Headless, no UI needed |
| Marmot client | MDK (Rust) | Same as Flutter app's core |
| WebRTC | libwebrtc or GStreamer | Audio-only participant |
| Transcription | faster-whisper (Python) or whisper.cpp (C++) | GPU-accelerated |
| Diarization | Per-track labeling (WebRTC) | No ML needed for calls |
| Summarization | Claude API or Ollama (local) | User configurable |
| IPC | gRPC or Unix sockets | Between Rust agent and Python transcription |

---

## Deployment Models

### 1. Self-Hosted Agent (Power Users)
- Run on your own server with GPU
- Full privacy — nothing leaves your infra
- Docker compose: agent + Whisper + Ollama

### 2. Burrow Cloud Agent (Convenience)
- Hosted by Burrow project
- Pay per meeting via Lightning micropayments
- Privacy trade-off: audio processed on Burrow servers (but still E2EE in transit)

### 3. OpenClaw Agent (Community)
- Run as an OpenClaw agent
- Any OpenClaw user can offer meeting assistant capacity
- Decentralized marketplace for AI meeting services

---

## Open Questions

1. **Whisper model size vs. latency** — large-v3 is most accurate but slow on CPU. Offer model selection?
2. **Multi-language calls** — Whisper handles this, but summarization LLM needs to match. Auto-detect and adapt?
3. **Recording consent** — Should the agent announce "this call is being transcribed"? Configurable per-group setting.
4. **Transcript format** — Standardize a Nostr event kind for meeting transcripts? Could become a NIP.
5. **Cost model** — Lightning micropayments per minute of transcription? Per summary? Flat per meeting?
