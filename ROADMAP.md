# Burrow — Roadmap

> The freedom tech communication platform. No phone numbers. Agent-native. Bitcoin-only.

Burrow is a secure messaging and collaboration platform built on the **Marmot protocol** (MLS + Nostr). It replaces Signal for messaging and Otter.ai for meeting intelligence — without centralized servers, phone numbers, or surveillance.

## What Makes Burrow Unique

- **No phone numbers** — Identity is a Nostr keypair. No PII required.
- **Agent-native** — AI agents are first-class participants, not add-ons.
- **Decentralized** — Nostr relays for transport, no single point of failure.
- **E2EE by default** — MLS protocol with forward secrecy and post-compromise security.
- **Bitcoin-only** — Zaps, payments, and tipping via Lightning. No fiat rails.
- **Open source** — MIT licensed, community-driven.
- **Cross-platform** — CLI, mobile, desktop.

---

## Phase 1: CLI Messenger ✅ COMPLETE

**TypeScript CLI for agent-human encrypted messaging over Marmot.**

- **Language:** TypeScript (Node.js ≥ 20)
- **Protocol:** `ts-mls` + `nostr-tools`
- **Source:** `src/`

### Completed Milestones
| # | Milestone | Status |
|---|-----------|--------|
| 1.1 | Nostr identity management (key generation, import, nsec/hex) | ✅ Complete |
| 1.2 | MLS KeyPackage generation and publishing (MIP-00, kind 443) | ✅ Complete |
| 1.3 | Group creation with Marmot extension 0xF2EE (MIP-01) | ✅ Complete |
| 1.4 | Member invitation via gift-wrapped MLS Welcome (MIP-02) | ✅ Complete |
| 1.5 | Encrypted group messaging with ephemeral keys (MIP-03) | ✅ Complete |
| 1.6 | Real-time message listening and decryption | ✅ Complete |
| 1.7 | File-based persistence (groups, keys, messages, MLS state) | ✅ Complete |
| 1.8 | Security review and hardening | ✅ Complete |

---

## Phase 2: Flutter Cross-Platform App ✅ COMPLETE

**Cross-platform messaging app with Rust cryptography engine.**

- **UI:** Flutter (Dart) with Material 3
- **Crypto:** Rust via MDK (Marmot Developer Kit) + `flutter_rust_bridge`
- **Platforms:** Android, iOS, Linux, macOS, Windows
- **Source:** `app/`

### Completed Milestones
| # | Milestone | Status |
|---|-----------|--------|
| 2.1 | Project scaffolding + Rust bridge setup (flutter_rust_bridge 2.11.1) | ✅ Complete |
| 2.2 | Nostr identity — create new keypair or import nsec/QR code | ✅ Complete |
| 2.3 | MLS KeyPackage generation and publishing via MDK | ✅ Complete |
| 2.4 | Group creation and listing | ✅ Complete |
| 2.5 | Member invitation — fetch KeyPackage, send gift-wrapped Welcome | ✅ Complete |
| 2.6 | Encrypted messaging — send/receive with real-time polling | ✅ Complete |
| 2.7 | Encrypted media — Blossom upload/download with ChaCha20-Poly1305 (MIP-04) | ✅ Complete |
| 2.8 | Accept pending invitations UI | ✅ Complete |
| 2.9 | Group info and member list screen | ✅ Complete |
| 2.10 | Security review and hardening (file permissions, hash verification, CI audit) | ✅ Complete |
| 2.11 | Unit and integration tests (Dart + Rust) | ✅ Complete |
| 2.12 | CI pipeline (fmt, clippy, analyze, test, cargo audit) | ✅ Complete |
| 2.13 | Documentation, README, build guides | ✅ Complete |
| 2.14 | Contact list tab (aggregated from group membership) | ✅ Complete |
| 2.15 | Mute/unmute conversations (persisted) | ✅ Complete |
| 2.16 | QR code identity import (camera scanner) | ✅ Complete |

### Key Decisions Made
- **MDK over ts-mls:** Rust MDK provides better performance and memory safety than the TypeScript MLS implementation
- **MdkMemoryStorage:** MLS state kept in RAM only — disk persistence deferred to Phase 3 (requires encrypted-at-rest design)
- **Riverpod + GoRouter:** Clean state management with auth-aware routing
- **Cargokit:** Handles Rust compilation for all Flutter target platforms

---

## Phase 3: Audio & Video Calls

**Goal:** 1:1 and group calls with E2EE, signaled over Nostr.

### Tech Stack
- **Media:** WebRTC (via `flutter_webrtc`)
- **Signaling:** Nostr gift-wrapped events (ephemeral, encrypted)
- **Encryption:** SRTP (WebRTC default) + Marmot MLS for key exchange
- **SFU:** Optional — mesh for small groups, SFU for 5+

### Milestones
| # | Milestone | Target |
|---|-----------|--------|
| 3.1 | Persistent encrypted storage (platform keychain + encrypted SQLite) | 🔜 Deferred |
| 3.2 | KeyPackage rotation and expiration | 🔜 Deferred |
| 3.3 | Push notifications (platform-native, MIP-05) | 🔜 Deferred |
| 3.4 | WebRTC signaling protocol design (Nostr events) | ✅ Complete |
| 3.5 | 1:1 audio calls | ✅ Complete |
| 3.6 | 1:1 video calls | ✅ Complete |
| 3.7 | Group audio calls (mesh, up to 5) | ✅ Complete |
| 3.8 | Group video calls | ✅ Complete |
| 3.9 | Speaker routing (earpiece ↔ speaker toggle) | ✅ Complete |
| 3.10 | Configurable TURN server (user settings override defaults) | ✅ Complete |
| 3.11 | Call UI on group info screen (Signal-style audio/video buttons) | ✅ Complete |
| 3.12 | Screen sharing | 🔜 Deferred |

### Insights from Phase 2
- `block_on` inside async `RwLock` guards should be refactored to proper async flow before adding real-time WebRTC
- Memory zeroization (`Zeroize` trait) needed for `nostr_sdk::Keys` — contribute upstream
- NIP-98 auth needed for Blossom media uploads before production use
- Persistent storage must encrypt MLS state at rest using platform keychain

### Design Doc
→ See [docs/PHASE3-DESIGN.md](docs/PHASE3-DESIGN.md)

---

## Phase 4: AI Meeting Assistant

**Goal:** Agent joins calls, transcribes, takes notes, extracts action items, sends summaries.

### Tech Stack
- **Transcription:** Whisper (local) or Deepgram/AssemblyAI (cloud)
- **Summarization:** Claude / local LLM via Ollama
- **Agent Identity:** Nostr keypair (the agent is a group member)
- **Delivery:** Summary sent as Marmot group message post-call
- **Speaker Diarization:** WhisperX or NeMo

### Milestones
| # | Milestone | Target |
|---|-----------|--------|
| 4.1 | Agent joins WebRTC call as audio-only participant | 🔜 Deferred |
| 4.2 | Real-time transcription pipeline (Rust whisper.cpp FFI + Flutter service) | ✅ Complete |
| 4.3 | Speaker diarization (WebRTC track-based, no ML needed) | ✅ Complete |
| 4.4 | Post-call summary generation (rule-based + LLM prompt builder) | ✅ Complete |
| 4.5 | Action item extraction and tracking (keyword + priority detection) | ✅ Complete |
| 4.6 | Live Q&A — ask the agent questions during the call | 🔜 Deferred |
| 4.7 | Searchable transcript archive | ✅ Complete |

### Design Doc
→ See [docs/PHASE4-DESIGN.md](docs/PHASE4-DESIGN.md)

---

## Bitcoin Integration (Cross-Phase)

- **Zaps:** Send sats to contacts via Lightning (NIP-57)
- **Payments in chat:** Send/receive Lightning invoices inline
- **Cashu ecash:** Optional privacy-preserving payments
- **Premium features:** Pay-per-use AI features via Lightning micropayments

---

## Community & Open Source

- **GitHub:** [CentauriAgent/burrow](https://github.com/CentauriAgent/burrow)
- **License:** MIT
- **Nostr:** Active on Nostr, ship updates as notes
- **Contributions welcome** — see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
