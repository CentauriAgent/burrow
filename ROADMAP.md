# Burrow — Roadmap

> The freedom tech communication platform. No phone numbers. Agent-native. Bitcoin-only.

Burrow is a secure messaging and collaboration platform built on the **Marmot protocol** (MLS + Nostr). It replaces Signal for messaging and Otter.ai for meeting intelligence — without centralized servers, phone numbers, or surveillance.

## What Makes Burrow Unique

- **No phone numbers** — Identity is a Nostr keypair. No PII required.
- **Agent-native** — AI agents are first-class participants, not add-ons.
- **Decentralized** — Nostr relays for transport, no single point of failure.
- **E2EE by default** — MLS protocol with forward secrecy and post-compromise security.
- **Bitcoin-only** — Zaps, payments, and tipping via Lightning. No fiat rails.
- **Open source** — MIT/AGPL licensed, community-driven.
- **Cross-platform** — CLI, mobile, desktop from day one.

---

## Phase 1: CLI Messenger (In Progress)

**Goal:** TypeScript CLI for agent-human encrypted messaging over Marmot.

### Tech Stack
- **Language:** TypeScript
- **Protocol:** Marmot via `marmot-ts` (early TypeScript MLS implementation)
- **Transport:** Nostr relays (`nostr-tools`)
- **Identity:** Nostr keypairs (nsec/npub)

### Milestones
| # | Milestone | Status |
|---|-----------|--------|
| 1.1 | Nostr identity management (key generation, import) | 🔧 In progress |
| 1.2 | 1:1 encrypted messaging (MLS two-party groups) | 🔧 In progress |
| 1.3 | Group creation and management | ⏳ Planned |
| 1.4 | Key package publishing and discovery | ⏳ Planned |
| 1.5 | Relay configuration and outbox model | ⏳ Planned |
| 1.6 | Agent-to-agent messaging (bot identities) | ⏳ Planned |

### Key Dependencies
- `marmot-ts` — TypeScript Marmot implementation (very early, may need contributions)
- `nostr-tools` — Nostr event creation, signing, relay management
- Phase 1 CLI repo: `CentauriAgent/burrow`

---

## Phase 2: Flutter Cross-Platform App

**Goal:** Beautiful, native-feeling messaging app for iOS, Android, and desktop.

### Tech Stack
- **UI Framework:** Flutter (Dart)
- **Crypto Engine:** Rust (whitenoise-rs / MDK via flutter_rust_bridge)
- **Bridge:** `flutter_rust_bridge` for Flutter ↔ Rust FFI
- **Storage:** SQLite (via MDK's mdk-sqlite-storage)
- **Media:** Blossom servers for encrypted media (MIP-04)
- **Push Notifications:** Platform-native (MIP-05)

### Milestones
| # | Milestone | Target |
|---|-----------|--------|
| 2.1 | Project scaffolding + Rust bridge setup | Month 1 |
| 2.2 | Nostr identity (create/import keys, profile display) | Month 1-2 |
| 2.3 | 1:1 encrypted chat (send/receive text) | Month 2-3 |
| 2.4 | Group chat (create, invite, manage members) | Month 3-4 |
| 2.5 | Media messages (images, audio, files via Blossom) | Month 4-5 |
| 2.6 | Push notifications | Month 5-6 |
| 2.7 | Contact discovery + social graph | Month 6 |
| 2.8 | Desktop support (macOS, Windows, Linux) | Month 6-7 |
| 2.9 | Beta release (TestFlight + Play Store beta) | Month 7-8 |

### Key Dependencies
- Phase 1 protocol work informs the data model
- `whitenoise-rs` (Rust crate) OR MDK directly as the crypto engine
- Reference: WhiteNoise Flutter app (`marmot-protocol/whitenoise-archive`)

### Detailed Design
→ See [docs/PHASE2-DESIGN.md](docs/PHASE2-DESIGN.md)

---

## Phase 3: Audio & Video Calls

**Goal:** 1:1 and group calls with E2EE, signaled over Nostr.

### Tech Stack
- **Media:** WebRTC (via `flutter_webrtc`)
- **Signaling:** Nostr gift-wrapped events (ephemeral, encrypted)
- **Encryption:** SRTP (WebRTC default) + Marmot MLS for key exchange
- **SFU (group calls):** Optional — can use mesh for small groups, SFU for 5+
- **TURN/STUN:** Self-hosted or community-operated servers

### Milestones
| # | Milestone | Target |
|---|-----------|--------|
| 3.1 | WebRTC signaling protocol design (Nostr events) | Month 8-9 |
| 3.2 | 1:1 audio calls | Month 9-10 |
| 3.3 | 1:1 video calls | Month 10-11 |
| 3.4 | Group audio calls (mesh, up to 5) | Month 11-12 |
| 3.5 | Group video calls | Month 12-13 |
| 3.6 | Screen sharing | Month 13-14 |

### Key Dependencies
- Phase 2 app must be functional
- STUN/TURN infrastructure
- NIP proposal for WebRTC signaling (no formal NIP exists yet — opportunity to author one)

### Detailed Design
→ See [docs/PHASE3-DESIGN.md](docs/PHASE3-DESIGN.md)

---

## Phase 4: AI Meeting Assistant

**Goal:** Agent joins calls, transcribes, takes notes, extracts action items, sends summaries.

### Tech Stack
- **Transcription:** Whisper (local) or Deepgram/AssemblyAI (cloud) — user choice
- **Summarization:** Claude / local LLM via Ollama
- **Agent Identity:** Nostr keypair (the agent is a group member)
- **Delivery:** Summary sent as Marmot group message post-call
- **Speaker Diarization:** WhisperX or NeMo for speaker identification

### Milestones
| # | Milestone | Target |
|---|-----------|--------|
| 4.1 | Agent joins WebRTC call as audio-only participant | Month 14-15 |
| 4.2 | Real-time transcription pipeline | Month 15-16 |
| 4.3 | Speaker diarization | Month 16-17 |
| 4.4 | Post-call summary generation | Month 17 |
| 4.5 | Action item extraction and tracking | Month 17-18 |
| 4.6 | Live Q&A — ask the agent questions during the call | Month 18-19 |
| 4.7 | Searchable transcript archive | Month 19-20 |

### Key Dependencies
- Phase 3 calls must work
- GPU resources for local Whisper (or cloud API budget)
- LLM for summarization

### Detailed Design
→ See [docs/PHASE4-DESIGN.md](docs/PHASE4-DESIGN.md)

---

## Bitcoin Integration (Cross-Phase)

Throughout all phases, Bitcoin/Lightning features are integrated:

- **Zaps:** Send sats to contacts via Lightning (NIP-57)
- **Payments in chat:** Send/receive Lightning invoices inline
- **Cashu ecash:** Optional privacy-preserving payments
- **Premium features:** Pay-per-use AI features via Lightning micropayments
- **No fiat. No tokens. Bitcoin only.**

---

## Community & Open Source

- **GitHub:** `CentauriAgent` org
- **License:** MIT (libraries) / AGPL-3.0 (apps)
- **Nostr:** Active on Nostr, ship updates as notes
- **Contributions welcome** — especially from the OpenClaw and Nostr communities

---

## Timeline Summary

```
Phase 1 (CLI)        ████████░░░░░░░░░░░░  Months 1-4
Phase 2 (Flutter)    ░░░░████████████░░░░  Months 4-11
Phase 3 (Calls)      ░░░░░░░░░░██████░░░░  Months 8-14
Phase 4 (AI)         ░░░░░░░░░░░░░░██████  Months 14-20
```

Phases overlap. Phase 2 development starts while Phase 1 CLI stabilizes. Phase 3 signaling design begins during Phase 2 development.
