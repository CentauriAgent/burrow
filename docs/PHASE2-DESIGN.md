# Phase 2: Flutter App — Detailed Design

## Overview

Burrow Phase 2 delivers a cross-platform messaging app using Flutter for UI and Rust for cryptography. The architecture mirrors WhiteNoise's proven approach: Flutter handles rendering and UX while a Rust core manages all MLS/Nostr operations via FFI.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Flutter UI (Dart)               │
│  ┌──────────┐ ┌──────────┐ ┌──────────────────┐ │
│  │  Screens  │ │ Widgets  │ │  State (Riverpod)│ │
│  └─────┬────┘ └─────┬────┘ └────────┬─────────┘ │
│        └────────────┼───────────────┘            │
│                     ▼                            │
│         ┌───────────────────────┐                │
│         │  Generated Bridge API │                │
│         │  (flutter_rust_bridge) │                │
│         └───────────┬───────────┘                │
├─────────────────────┼───────────────────────────-┤
│                     ▼           Rust Core         │
│  ┌─────────────────────────────────────────────┐ │
│  │              Burrow Core Crate               │ │
│  │  ┌──────────┐ ┌─────────┐ ┌──────────────┐  │ │
│  │  │  Account  │ │  Groups │ │   Messages   │  │ │
│  │  │ Manager   │ │ Manager │ │   Manager    │  │ │
│  │  └────┬─────┘ └────┬────┘ └──────┬───────┘  │ │
│  │       └────────────┼─────────────┘           │ │
│  │                    ▼                         │ │
│  │  ┌─────────────────────────────────────────┐ │ │
│  │  │    MDK (Marmot Development Kit)         │ │ │
│  │  │  ┌─────────┐ ┌────────┐ ┌────────────┐ │ │ │
│  │  │  │ OpenMLS  │ │ Nostr  │ │  Storage   │ │ │ │
│  │  │  │ (MLS)    │ │ Client │ │  (SQLite)  │ │ │ │
│  │  │  └─────────┘ └────────┘ └────────────┘ │ │ │
│  │  └─────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
         │              │              │
         ▼              ▼              ▼
    ┌─────────┐  ┌───────────┐  ┌──────────┐
    │  Nostr   │  │  Blossom  │  │  Local   │
    │  Relays  │  │  Servers  │  │  SQLite  │
    └─────────┘  └───────────┘  └──────────┘
```

---

## WhiteNoise Analysis — What We Learn and Reuse

### WhiteNoise Architecture (Reference Implementation)

WhiteNoise is built by the Parres/Marmot team and is the canonical Marmot messaging app:

- **Repos:**
  - `marmot-protocol/whitenoise` — Active Flutter app (124 commits, multi-platform: Android, iOS, Linux, macOS, Windows, Web)
  - Uses `flutter_rust_bridge` with embedded `rust/` directory for MLS backend
  - Has `widgetbook` for component-driven UI design
  - `marmot-protocol/mdk` — Marmot Development Kit (the protocol library)

- **Architecture:** Flutter + Rust via `flutter_rust_bridge`. The Rust crate (`whitenoise-rs`) wraps MDK and exposes a high-level API to Flutter.

- **Key Libraries:**
  - `OpenMLS` — MLS protocol implementation (RFC 9420)
  - `rust-nostr` — Nostr event handling, relay connections
  - `mdk-sqlite-storage` — Persistent MLS state
  - `flutter_rust_bridge` — Dart ↔ Rust code generation

- **Build System:** `just` task runner, `cargo` for Rust, `flutter` CLI
- **CI:** GitHub Actions (fmt, clippy, analyze, tests)

### What We Can Reuse

| Component | Reuse? | Notes |
|-----------|--------|-------|
| MDK (Marmot Development Kit) | ✅ Direct dependency | Core protocol library — use as-is |
| OpenMLS integration | ✅ Via MDK | Don't reinvent — MDK handles MLS |
| flutter_rust_bridge pattern | ✅ Same approach | Proven FFI pattern for Flutter ↔ Rust |
| Storage layer (mdk-sqlite-storage) | ✅ Direct dependency | SQLite storage with migrations |
| whitenoise-rs crate | 🤔 Evaluate | Could depend on it OR build our own wrapper around MDK |
| Flutter UI code | ❌ Build fresh | WhiteNoise UI is fine but Burrow has different UX goals |
| Docker dev setup (relays + blossom) | ✅ Reuse | Local testing infra |

### What We Build Fresh

- **Agent integration** — First-class bot/agent participants (WhiteNoise is human-only)
- **Meeting features** — Call UI, transcription display, action items (Phase 3-4 hooks)
- **Bitcoin/Lightning** — Zaps, in-chat payments
- **Burrow-specific UX** — Our design language, onboarding flow

---

## Flutter ↔ Rust Bridge Strategy

### flutter_rust_bridge (v2)

The bridge auto-generates Dart bindings from Rust function signatures.

**How it works:**
1. Define public Rust functions in `rust/src/api/` modules
2. Run `flutter_rust_bridge_codegen generate`
3. Generated Dart code appears in `lib/src/rust/`
4. Call Rust from Dart like normal async functions

**Example flow:**
```rust
// rust/src/api/account.rs
pub fn create_account(display_name: String) -> Result<AccountInfo, BurrowError> {
    let mdk = MdkInstance::new()?;
    mdk.create_identity(&display_name)
}

pub fn send_message(group_id: String, content: String) -> Result<(), BurrowError> {
    let mdk = get_mdk()?;
    mdk.send_group_message(&group_id, content.as_bytes())
}
```

```dart
// Dart side (auto-generated bridge)
final account = await api.createAccount(displayName: "Alice");
await api.sendMessage(groupId: chatId, content: "Hello!");
```

**Platform packaging:**
- **iOS:** Rust compiles to static library (.a), linked via Xcode
- **Android:** Rust compiles to shared library (.so) per ABI (arm64, x86_64)
- **macOS/Linux/Windows:** Rust compiles to dynamic library (.dylib/.so/.dll)

The `flutter_rust_bridge` codegen + `cargo-ndk` (Android) + `cargo-lipo` (iOS) handle cross-compilation.

---

## UI/UX Design

### Screens

#### 1. Onboarding
- **Generate new identity** or **Import existing** (nsec paste or NIP-46 signer)
- Set display name and optional avatar
- Choose relays (defaults provided, advanced users can customize)
- No phone number. No email. No verification.

#### 2. Chat List (Home)
- List of conversations sorted by last message
- Unread badges
- Search bar (filter conversations)
- FAB: New chat / New group
- Bottom nav: Chats | Contacts | Calls (Phase 3) | Settings

#### 3. Chat View
- Message bubbles (sent/received)
- Timestamps, read receipts (optional)
- Media preview (images, audio playback)
- Input bar: text field + attachment button + send
- Group: member list drawer, admin controls
- Zap button on messages (send sats)

#### 4. Contact / Profile View
- Nostr profile info (name, avatar, about, NIP-05)
- npub display + QR code
- Start chat / Add to group
- Zap profile

#### 5. Settings
- Identity management (view npub/nsec, backup)
- Relay configuration
- Notification preferences
- Theme (dark/light)
- Bitcoin/Lightning wallet connection
- About / Open source info

### Design Language
- **Dark mode first** (freedom tech aesthetic)
- Material 3 with custom Burrow theme
- Accent color: Bitcoin orange (#F7931A) on dark surfaces
- Clean, minimal — not cluttered
- Marmot mascot for empty states and onboarding

---

## MVP Feature List

### Must Have (v0.1)
- [ ] Create/import Nostr identity
- [ ] 1:1 encrypted messaging (text)
- [ ] Group creation and messaging
- [ ] Member invite/remove
- [ ] Contact list (by npub)
- [ ] Message history (local SQLite)
- [ ] Basic push notifications
- [ ] Dark theme

### Should Have (v0.2)
- [ ] Image messages (Blossom upload + encrypted)
- [ ] Audio messages (voice recording)
- [ ] QR code sharing (npub)
- [ ] Desktop builds (macOS, Linux, Windows)
- [ ] Lightning zaps on messages
- [ ] Profile editing

### Nice to Have (v0.3+)
- [ ] Link previews
- [ ] Message reactions (emoji)
- [ ] Typing indicators
- [ ] Message search
- [ ] Multiple accounts
- [ ] NIP-46 remote signer support

---

## Dependencies

### Dart/Flutter
```yaml
dependencies:
  flutter_rust_bridge: ^2.0.0
  riverpod: ^2.0.0          # State management
  go_router: ^latest         # Navigation
  hive: ^latest              # Local key-value cache
  image_picker: ^latest      # Media selection
  qr_flutter: ^latest        # QR code display
  mobile_scanner: ^latest    # QR code scanning
  flutter_local_notifications: ^latest
  share_plus: ^latest
```

### Rust (Cargo.toml)
```toml
[dependencies]
mdk-core = { git = "https://github.com/marmot-protocol/mdk" }
mdk-sqlite-storage = { git = "https://github.com/marmot-protocol/mdk" }
flutter_rust_bridge = "2"
nostr-sdk = "0.35"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### Build Tools
- Flutter SDK 3.24+
- Rust stable (1.90+)
- `just` task runner
- `cargo-ndk` (Android cross-compilation)
- `flutter_rust_bridge_codegen`
- Docker (local relay + blossom for dev/test)

---

## Project Structure

```
burrow/
├── lib/                          # Flutter/Dart
│   ├── main.dart
│   ├── app.dart
│   ├── config/
│   │   ├── theme.dart
│   │   ├── routes.dart
│   │   └── providers.dart
│   ├── domain/
│   │   ├── models/              # Dart data models
│   │   ├── repositories/       # Data access layer
│   │   └── services/           # Business logic
│   ├── ui/
│   │   ├── screens/
│   │   │   ├── onboarding/
│   │   │   ├── chat_list/
│   │   │   ├── chat_view/
│   │   │   ├── contacts/
│   │   │   └── settings/
│   │   └── widgets/            # Reusable components
│   └── src/rust/               # Generated bridge code (don't edit)
├── rust/                        # Rust core
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       └── api/
│           ├── mod.rs
│           ├── account.rs      # Identity management
│           ├── groups.rs       # Group CRUD + messaging
│           ├── messages.rs     # Send/receive/decrypt
│           ├── contacts.rs     # Contact discovery
│           ├── media.rs        # Blossom upload/download
│           └── relays.rs       # Relay management
├── flutter_rust_bridge.yaml
├── justfile
├── pubspec.yaml
└── docker-compose.yml          # Local dev relays + blossom
```

---

## Connection to Phase 1 CLI

The Phase 1 CLI (TypeScript) and Phase 2 Flutter app share:

- **Same Marmot protocol** — Messages are interoperable
- **Same Nostr identity** — Import the same nsec into either client
- **Same relays** — Both connect to the same relay infrastructure
- **Same MLS groups** — A group created in CLI is visible in the Flutter app

The CLI uses `marmot-ts` while the Flutter app uses MDK (Rust). Both implement the same Marmot MIPs, so they're interoperable at the protocol level.

Over time, the CLI may also switch to using MDK via Rust FFI (Node.js native addon) for consistency.

---

## Development Plan

### Month 1: Foundation
- Scaffold Flutter project with Rust bridge
- Set up CI (GitHub Actions: fmt, clippy, analyze, test)
- Implement identity creation/import in Rust
- Build onboarding screens

### Month 2-3: Core Messaging
- Implement MLS group creation via MDK
- Build chat list and chat view screens
- Send and receive text messages
- Local message storage (SQLite)

### Month 4-5: Media & Polish
- Blossom integration for encrypted media
- Image and audio messages
- Push notifications
- Group management UI

### Month 6-7: Multi-Platform & Beta
- Desktop builds (macOS first, then Windows/Linux)
- Contact discovery and social graph
- Performance optimization
- Beta release

---

## Open Questions

1. **Use whitenoise-rs directly or just MDK?** — whitenoise-rs adds convenience wrappers around MDK. Could depend on it, or build our own thinner wrapper with agent-specific features.

2. **License compatibility** — whitenoise-rs is AGPL-3.0, MDK is MIT. If we depend on whitenoise-rs, Burrow must be AGPL. If we use MDK directly, we can be MIT.

3. **marmot-ts maturity** — The TypeScript implementation is very early. Phase 1 CLI may need to contribute significantly to marmot-ts, or pivot to using MDK via NAPI-RS.

4. **Relay selection UX** — How much relay configuration do we expose? Default relays for most users, power-user settings for advanced.
