# Burrow Architecture

> Technical architecture of Burrow — a Marmot protocol (MLS + Nostr) encrypted messenger.

## Overview

Burrow implements the [Marmot protocol](https://github.com/marmot-protocol) for decentralized end-to-end encrypted messaging. It has two implementations:

- **Phase 1 (CLI):** TypeScript, using `ts-mls` and `nostr-tools`
- **Phase 2 (App):** Flutter + Rust, using MDK (Marmot Developer Kit) via `flutter_rust_bridge`

Both target the same Marmot MIPs and are interoperable.

### Design Philosophy

- **Nostr identity is the only identity** — A 32-byte keypair. No phone numbers, no email, no KYC.
- **Agent-native** — AI agents are first-class participants, not afterthoughts.
- **Protocol-first** — Strict compliance with Marmot MIPs ensures interoperability with other implementations (e.g., WhiteNoise).
- **Minimal dependencies** — Use proven cryptographic libraries, avoid reinventing.

---

## Phase 2 Architecture: Flutter App

### System Architecture

```
┌──────────────────────────────────────────────────┐
│                   Flutter App                     │
│                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐ │
│  │  Screens   │  │  Widgets   │  │   Router    │ │
│  │ (UI Layer) │  │ (Reusable) │  │ (GoRouter)  │ │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘ │
│        │               │               │        │
│        └───────┬───────┘               │        │
│                ▼                       │        │
│  ┌──────────────────────┐              │        │
│  │   Riverpod Providers │◄─────────────┘        │
│  │   (State Management) │                       │
│  └──────────┬───────────┘                       │
│             │                                    │
│             ▼                                    │
│  ┌──────────────────────┐                       │
│  │ flutter_rust_bridge   │   Generated FFI       │
│  │ (frb_generated.dart) │   bindings             │
│  └──────────┬───────────┘                       │
└─────────────┼────────────────────────────────────┘
              │ FFI
              ▼
┌──────────────────────────────────────────────────┐
│                   Rust Crate                      │
│            (rust_lib_burrow_app)                  │
│                                                  │
│  ┌──────────────────────────────────────────────┐│
│  │                  api/                         ││
│  │                                              ││
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ││
│  │  │ account  │  │ identity │  │ keypackage│  ││
│  │  │ create/  │  │ Nostr    │  │ MIP-00    │  ││
│  │  │ load key │  │ profiles │  │ publish   │  ││
│  │  └──────────┘  └──────────┘  └───────────┘  ││
│  │                                              ││
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ││
│  │  │  group   │  │  invite  │  │  message  │  ││
│  │  │ create/  │  │ send/    │  │ send/recv │  ││
│  │  │ list     │  │ accept   │  │ encrypt   │  ││
│  │  └──────────┘  └──────────┘  └───────────┘  ││
│  │                                              ││
│  │  ┌──────────┐  ┌──────────┐  ┌───────────┐  ││
│  │  │  media   │  │  relay   │  │   state   │  ││
│  │  │ Blossom  │  │ connect/ │  │ global    │  ││
│  │  │ up/down  │  │ publish  │  │ BurrowState│ ││
│  │  └──────────┘  └──────────┘  └───────────┘  ││
│  └──────────────────────────────────────────────┘│
│                                                  │
│  ┌──────────────────────────────────────────────┐│
│  │              Dependencies                     ││
│  │  mdk-core  │  nostr-sdk  │  reqwest          ││
│  │  (MLS/MIP) │  (Nostr)    │  (HTTP/Blossom)   ││
│  └──────────────────────────────────────────────┘│
└──────────────────────────────────────────────────┘
```

### Rust Crate Modules (`app/rust/src/api/`)

| Module | Responsibility |
|--------|---------------|
| **`state.rs`** | Global `BurrowState` (Nostr keys, MDK client, relay pool) — held in a `tokio::sync::RwLock` |
| **`account.rs`** | Create/load Nostr keypairs, save/load nsec to disk (0o600 permissions) |
| **`identity.rs`** | Fetch and parse Nostr kind 0 profiles (display names, avatars) |
| **`keypackage.rs`** | Generate and publish MLS KeyPackages (kind 443) per MIP-00 |
| **`group.rs`** | Create MLS groups with Marmot extension, list groups |
| **`invite.rs`** | Fetch recipient's KeyPackage, create MLS Welcome, gift-wrap and publish |
| **`message.rs`** | Encrypt/decrypt MLS application messages, publish kind 445 events |
| **`media.rs`** | Blossom media upload/download with ChaCha20-Poly1305 encryption (MIP-04) |
| **`relay.rs`** | Connect to relay pool, publish events, subscribe to filters |
| **`error.rs`** | Unified `BurrowError` enum with `thiserror` |

### Flutter App Modules (`app/lib/`)

#### Screens

| Screen | Route | Description |
|--------|-------|-------------|
| `onboarding_screen.dart` | `/onboarding` | Welcome screen — create or import identity |
| `create_identity_screen.dart` | `/create-identity` | Generate new Nostr keypair |
| `import_identity_screen.dart` | `/import-identity` | Import existing nsec key |
| `home_screen.dart` | `/home` | Main screen with chat list |
| `chat_list_screen.dart` | (embedded) | List of group conversations |
| `chat_view_screen.dart` | (pushed) | Message view for a group |
| `create_group_screen.dart` | `/create-group` | Create new encrypted group |
| `invite_members_screen.dart` | `/invite/:groupId` | Add members to a group |
| `pending_invites_screen.dart` | `/invites` | View/accept pending invitations |
| `group_info_screen.dart` | `/group-info/:groupId` | Group details and member list |
| `profile_screen.dart` | `/profile` | User identity and settings |

#### Providers (Riverpod)

| Provider | Responsibility |
|----------|---------------|
| `auth_provider.dart` | Login state, account initialization, logout |
| `groups_provider.dart` | Group list, group creation |
| `group_provider.dart` | Single group state and operations |
| `messages_provider.dart` | Message send/receive, real-time polling |
| `invite_provider.dart` | Send invites, fetch/accept pending invites |
| `relay_provider.dart` | Relay connection state |

#### Widgets

| Widget | Description |
|--------|-------------|
| `chat_list_tile.dart` | Group conversation list item |
| `chat_bubble.dart` | Individual message bubble in chat view |

#### Router

GoRouter handles navigation with auth-aware redirects — unauthenticated users are redirected to onboarding, authenticated users skip it.

### Data Flow: Sending a Message (Flutter App)

```
User taps Send in ChatViewScreen
            │
            ▼
┌───────────────────────────┐
│ MessagesProvider          │  Dart (Riverpod)
│ calls Rust send_message() │
└───────────┬───────────────┘
            │ FFI via flutter_rust_bridge
            ▼
┌───────────────────────────┐
│ api/message.rs            │  Rust
│ 1. Get BurrowState        │
│ 2. Build inner event      │
│ 3. MDK encrypt (MLS)      │
│ 4. NIP-44 wrap            │
│ 5. Sign with ephemeral key│
│ 6. Publish kind 445       │
└───────────────────────────┘
            │
            ▼
      Nostr Relays
```

### Key Dependencies (Rust)

| Crate | Purpose |
|-------|---------|
| `mdk-core` | Marmot protocol — MLS groups, key schedules, message encryption |
| `mdk-memory-storage` | In-memory MLS state storage (no disk persistence yet) |
| `nostr-sdk` 0.44 | Nostr key management, event signing, relay communication |
| `flutter_rust_bridge` 2.11.1 | Dart ↔ Rust FFI code generation |
| `reqwest` (rustls-tls) | HTTP client for Blossom media servers |
| `sha2` | SHA-256 hash verification for downloaded media |

### Key Dependencies (Flutter)

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `go_router` | Declarative routing with auth guards |
| `flutter_rust_bridge` | Generated Rust FFI bindings |
| `intl` | Internationalization / date formatting |

---

## Phase 1 Architecture: TypeScript CLI

### Module Breakdown

```
src/
├── index.ts              # CLI entry point (Commander.js)
├── types/index.ts        # Protocol constants, interfaces, defaults
├── crypto/
│   ├── identity.ts       # Nostr keypair management (load/generate)
│   ├── nip44.ts          # NIP-44 encryption (group messages + gift-wrapping)
│   └── utils.ts          # Hex/bytes conversion utilities
├── mls/
│   ├── keypackage.ts     # MLS KeyPackage generation (MIP-00)
│   ├── extensions.ts     # Marmot Group Data extension 0xF2EE (MIP-01)
│   └── group.ts          # Group lifecycle: create, add member, send, receive
├── nostr/
│   ├── relay.ts          # Relay pool, event signing, ephemeral keys
│   └── events.ts         # Event builders for kinds 443, 444, 445
├── store/index.ts        # File-based persistence (groups, keys, messages)
└── cli/
    ├── init.ts           # `burrow init` — identity + KeyPackage publishing
    ├── group.ts          # `burrow create-group` / `burrow groups`
    ├── invite.ts         # `burrow invite` — fetch KeyPackage, send Welcome
    ├── send.ts           # `burrow send` — encrypt and publish
    └── read.ts           # `burrow read` / `burrow listen` — decrypt and display
```

### Data Flow: Sending a Message (CLI)

```
User types: burrow send <group-id> "Hello everyone"
                │
                ▼
┌─────────────────────────────────┐
│ 1. Load identity (secret key)   │  crypto/identity.ts
│ 2. Load group + MLS state       │  store/index.ts
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 3. Build unsigned kind 9 event  │  nostr/events.ts
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 4. MLS encrypt (application     │  mls/group.ts (ts-mls)
│    message) → ciphertext bytes  │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 5. NIP-44 encrypt using         │  crypto/nip44.ts
│    exporter_secret as key       │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 6. Build kind 445 event with    │  nostr/events.ts
│    ephemeral keypair + h tag    │
│ 7. Publish to Nostr relays      │  nostr/relay.ts
│ 8. Save updated MLS state       │  store/index.ts
└─────────────────────────────────┘
```

---

## Marmot Protocol Compliance

Both implementations comply with:

| MIP | Title | CLI | App |
|-----|-------|-----|-----|
| MIP-00 | Key Packages (kind 443) | ✅ | ✅ |
| MIP-01 | Group Management (extension 0xF2EE) | ✅ | ✅ |
| MIP-02 | Welcome Events (kind 444 + NIP-59) | ✅ | ✅ |
| MIP-03 | Group Messages (kind 445 + NIP-44) | ✅ | ✅ |
| MIP-04 | Encrypted Media (Blossom) | ❌ | ✅ |

## Security Model

### Encryption Layers

| Layer | Protects | Mechanism |
|-------|----------|-----------|
| **MLS (inner)** | Message content, forward secrecy, post-compromise security | RFC 9420 |
| **NIP-44 (outer)** | MLS ciphertext from non-members | Exporter secret as symmetric key |
| **Ephemeral keys** | Sender identity on kind 445 events | Random keypair per message |
| **NIP-59 gift-wrap** | Welcome recipient identity | Encrypted kind 1059 wrapper |
| **ChaCha20-Poly1305** | Media file contents (MIP-04) | AEAD encryption before Blossom upload |

For detailed findings, see [SECURITY.md](SECURITY.md).

## Dependencies (CLI)

| Package | Purpose |
|---------|---------|
| `ts-mls` ^1.6.1 | MLS protocol (RFC 9420) |
| `nostr-tools` ^2.23.1 | Nostr events and relays |
| `@noble/curves` ^2.0.1 | secp256k1/schnorr |
| `@noble/hashes` ^2.0.1 | SHA-256, hex/bytes |
| `commander` ^14.0.3 | CLI framework |
