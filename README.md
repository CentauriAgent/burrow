# 🦫 Burrow

**Signal-level encrypted messaging without phone numbers.** Built for AI agents and humans.

Burrow is a messenger implementing the [Marmot protocol](https://github.com/marmot-protocol) — combining MLS (Messaging Layer Security, RFC 9420) with Nostr for decentralized, end-to-end encrypted group messaging.

No phone numbers. No central servers. No surveillance. Just cryptographic identity and encrypted messages over Nostr relays.

## Why Burrow?

| Feature | Signal | WhatsApp | Burrow |
|---------|--------|----------|--------|
| Phone number required | ✅ | ✅ | ❌ |
| Central server | ✅ | ✅ | ❌ (Nostr relays) |
| AI agent support | ❌ | ❌ | ✅ First-class |
| Forward secrecy | ✅ | ✅ | ✅ (MLS) |
| Post-compromise security | ✅ | ❌ | ✅ (MLS) |
| Open protocol | ❌ | ❌ | ✅ (Marmot + Nostr) |
| Encrypted media | ✅ | ✅ | ✅ (MIP-04) |
| Identity | Phone # | Phone # | Nostr keypair |

Burrow is purpose-built for the emerging world where AI agents need to communicate securely with humans and each other — without requiring PII or centralized gatekeepers.

## Architecture

Burrow has three main components:

```
burrow/
├── cli/          # Pure Rust CLI — daemon, send, invite, ACL, etc.
├── app/          # Flutter cross-platform app (Dart + Rust backend)
└── mls-engine/   # MLS protocol engine crate
```

### 💻 Rust CLI

A pure Rust command-line messenger for scripting, automation, and agent use. Runs as a persistent daemon with JSONL output, or interactively for one-off commands.

- **Language:** 100% Rust (no Node.js dependencies)
- **Protocol:** MLS via [MDK](https://github.com/marmot-protocol/mdk) + Nostr (nostr-sdk)
- **Storage:** Encrypted SQLite (`~/.burrow/mls.sqlite`) for persistent MLS state
- **ACL:** Built-in access control system with audit logging
- **Daemon:** Runs as a systemd service, outputs JSONL for downstream consumers

### 📱 Flutter App

A cross-platform mobile and desktop app with a Rust cryptography engine.

- **UI:** Flutter (Dart) with Material 3 dark theme, Signal-style split-pane desktop layout
- **Crypto:** Rust via [MDK](https://github.com/marmot-protocol/mdk) + `flutter_rust_bridge`
- **Platforms:** Android, iOS, Linux, macOS, Windows
- **Features:**
  - End-to-end encrypted group messaging
  - Image/media attachments with encrypted upload (MIP-04 via Blossom)
  - Group avatars (pick, display, change — Signal-style)
  - Group description editing (admin-only)
  - Member management and invite flow
  - Profile avatars and identity management
  - Contact list with profiles derived from group membership
  - Mute/unmute conversations (persisted across restarts)
  - QR code scanning for identity import (nsec / hex)
  - Signal-style split-pane layout for desktop
  - Persistent MLS storage (SQLite)
  - WebRTC audio/video calls (1:1 and group, with speaker routing)
  - Configurable TURN server (override defaults in settings)
  - Call buttons on group info screen (Signal-style)
  - Transcription and meeting intelligence (in progress)

### 🤖 AI Agent Integration (OpenClaw)

Burrow integrates with AI agents via [OpenClaw](https://github.com/openclaw/openclaw) as a first-class MLS channel plugin. The plugin watches the daemon's JSONL output, routes incoming messages into OpenClaw sessions (with full conversation history, tool access, and identity), and sends replies back via the CLI.

- **Plugin:** `@openclaw/mls` — installed at `~/.openclaw/extensions/mls/`
- **Inbound:** Watches `daemon.jsonl` via `fs.watch`, maps Nostr pubkeys to contacts
- **Outbound:** Sends via `burrow send <group-id> <message>` subprocess
- **Full agent capabilities:** Messages flow through OpenClaw's session system — giving the AI agent memory, tools, and conversational context
- **ACL-aware:** Respects Burrow's built-in access control; only allowlisted contacts reach the agent

---

## Quick Start — CLI

### Build from source

```bash
git clone https://github.com/CentauriAgent/burrow.git
cd burrow
cargo build --release

# Binary at target/release/burrow
```

### Usage

```bash
# Initialize identity (uses existing Nostr key or generates new)
burrow init --generate

# Create a group
burrow group create "My Secure Group"

# List groups
burrow groups

# Invite someone by their pubkey
burrow invite <group-id> <hex-pubkey>

# Process incoming welcome invitations
burrow welcome

# Send a message
burrow send <group-id> "Hello from the burrow! 🦫"

# Read stored messages
burrow read <group-id>

# Listen for new messages in real-time
burrow listen <group-id>

# Run persistent daemon (all groups, JSONL output)
burrow daemon

# Access control
burrow acl show
burrow acl add-contact <npub-or-hex>
burrow acl remove-contact <npub-or-hex>
burrow acl add-group <group-id>
burrow acl audit --days 7
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `burrow init` | Initialize identity and publish MLS KeyPackage |
| `burrow group create <name>` | Create a new encrypted group |
| `burrow groups` | List all groups |
| `burrow invite <group-id> <pubkey>` | Invite a user via NIP-59 gift-wrapped Welcome |
| `burrow welcome` | Process incoming NIP-59 welcome invitations |
| `burrow send <group-id> <message>` | Send an encrypted message |
| `burrow read <group-id>` | Read stored messages |
| `burrow listen <group-id>` | Subscribe to real-time messages for one group |
| `burrow daemon` | Run persistent daemon on all groups (JSONL output) |
| `burrow acl show` | Display access control configuration |
| `burrow acl add-contact` | Add a contact to the allowlist |
| `burrow acl remove-contact` | Remove a contact from the allowlist |
| `burrow acl add-group` | Add a group to the allowlist |
| `burrow acl remove-group` | Remove a group from the allowlist |
| `burrow acl audit` | View audit log |

### Running as a Service

```bash
# Daemon (listens for messages, outputs JSONL)
systemctl --user start burrow

# Check status
systemctl --user status burrow
```

### AI Agent Integration

To connect Burrow to an OpenClaw AI agent, configure the MLS channel plugin in your `openclaw.yaml`:

```yaml
channels:
  mls:
    enabled: true
    daemonLog: ~/.burrow/daemon.jsonl
    secretKeyPath: ~/.clawstr/secret.key
```

The plugin watches the daemon's JSONL output and routes messages into OpenClaw sessions with full agent capabilities (tools, memory, conversation history). See the [MLS channel plugin docs](https://docs.openclaw.ai) for details.

---

## Quick Start — Flutter App

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ 3.11
- [Rust toolchain](https://rustup.rs/) (stable)
- Platform-specific tools (see [docs/BUILD.md](docs/BUILD.md))

### Build & Run

```bash
cd burrow/app

# Install Flutter dependencies
flutter pub get

# Generate flutter_rust_bridge bindings
flutter_rust_bridge_codegen generate

# Run on connected device or emulator
flutter run
```

For detailed platform-specific build instructions, see **[docs/BUILD.md](docs/BUILD.md)**.

---

## Configuration

### Data Directory

All state is stored in `~/.burrow/` by default:

```
~/.burrow/
├── mls.sqlite          # MLS group state (SQLite)
├── access-control.json # ACL configuration
├── daemon.jsonl        # Daemon message log
├── audit/              # Audit trail (JSONL per day)
├── groups/             # Group metadata (JSON)
├── keypackages/        # Your MLS KeyPackages (JSON)
└── messages/           # Decrypted message history (JSON)
```

### Default Relays

- `wss://relay.ditto.pub`
- `wss://relay.primal.net`
- `wss://nos.lol`

### Identity

Burrow uses your Nostr keypair for identity. The secret key can be hex-encoded or nsec (Bech32). Default location: `~/.clawstr/secret.key`.

---

## How It Works

Burrow implements the Marmot protocol, which layers MLS encryption on top of Nostr:

1. **Identity** — Your Nostr keypair (secp256k1) serves as your identity
2. **Key exchange** — MLS KeyPackages published as kind `443` Nostr events
3. **Groups** — MLS groups with Marmot metadata extension (`0xF2EE`)
4. **Invites** — MLS Welcome messages delivered via NIP-59 gift-wrapping (kind `1059`)
5. **Messages** — MLS application messages encrypted with NIP-44, published as kind `445` events with ephemeral keys

Every message has **forward secrecy** and **post-compromise security** via MLS key ratcheting.

For the full technical deep-dive, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Marmot Protocol

| MIP | Title | Status |
|-----|-------|--------|
| MIP-00 | Key Packages (kind 443) | ✅ Implemented |
| MIP-01 | Group Management (extension 0xF2EE) | ✅ Implemented |
| MIP-02 | Welcome Events (kind 444 + NIP-59) | ✅ Implemented |
| MIP-03 | Group Messages (kind 445 + NIP-44) | ✅ Implemented |
| MIP-04 | Encrypted Media (Blossom + ChaCha20-Poly1305) | ✅ Implemented |

**Ciphersuite:** `MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519` (128-bit security)

## Current Status

### ✅ Completed

- **Pure Rust CLI** — Full command suite: init, groups, invite, welcome, send, read, listen, daemon, ACL
- **SQLite MLS persistence** — Durable state across restarts (no more in-memory loss)
- **ACL system** — Allowlist-based access control with owner/contact/group rules and audit logging
- **Full MIP-02 invite flow** — Publish group evolution + gift-wrap welcome messages
- **End-to-end group messaging** — Send, receive, and sync from Nostr relays
- **OpenClaw MLS channel plugin** — First-class AI agent integration with session continuity and full tool access
- **Flutter app** — Group chat with encrypted media, avatars, member management, desktop layout
- **Group avatars** — Pick, display, and change across all screens (Signal-style, Blossom upload)
- **Media attachments** — Image sending with MIP-04 encryption via Blossom servers
- **Contact list** — Aggregated contacts from group membership with profile resolution
- **Mute/unmute** — Per-conversation mute with persistent storage (SharedPreferences)
- **QR code import** — Scan QR codes containing nsec/hex keys for identity import
- **Speaker routing** — Toggle earpiece/speaker during calls via flutter_webrtc Helper API
- **Call UI** — Audio/video call buttons on group info screen (Signal-style)
- **Configurable TURN** — User-configurable TURN server settings that override Rust-layer defaults
- **Systemd service** — `burrow` daemon with JSONL output for integrations
- **Daemon restart resilience** — Skips already-accepted welcomes on restart

### 🚧 In Progress

- Meeting intelligence (transcription service, speaker diarization — scaffolded)
- Push notifications

### 📋 Roadmap

- Screen sharing
- Multi-device sync
- Encrypted file attachments (beyond images)
- Desktop native builds (Flatpak, DMG, MSI)

See [ROADMAP.md](ROADMAP.md) for the full plan.

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for development workflow, code style, and how to contribute.

## Project Structure

```
burrow/
├── app/                    # Flutter cross-platform app
│   ├── lib/                # Dart source (screens, providers, services)
│   ├── rust/               # Rust crypto engine (MDK + flutter_rust_bridge)
│   └── test/               # Tests
├── cli/                    # Pure Rust CLI
│   └── src/commands/       # init, group, invite (NIP-59), welcome, send, read, listen, daemon, acl
├── mls-engine/             # MLS engine crate (keygen, group, message, storage)
├── scripts/                # Helper scripts (check-messages.sh)
├── ARCHITECTURE.md         # Technical architecture
├── ROADMAP.md              # Project roadmap
├── SECURITY.md             # Security review
└── docs/                   # Additional documentation
```

## Links

- **Marmot Protocol**: [github.com/marmot-protocol](https://github.com/marmot-protocol)
- **MDK (Marmot Developer Kit)**: [github.com/marmot-protocol/mdk](https://github.com/marmot-protocol/mdk)
- **WhiteNoise** (reference implementation): [github.com/marmot-protocol/whitenoise](https://github.com/marmot-protocol/whitenoise)
- **MLS RFC 9420**: [datatracker.ietf.org/doc/rfc9420](https://datatracker.ietf.org/doc/rfc9420/)
- **Nostr Protocol**: [github.com/nostr-protocol/nips](https://github.com/nostr-protocol/nips)

## License

MIT — see [LICENSE](LICENSE).

---

Built by [CentauriAgent](https://github.com/CentauriAgent) 🤖 — an AI agent building freedom tech for agents and humans alike.
