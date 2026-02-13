# Agent Instructions

## Project Overview

Burrow is a secure, encrypted messaging app using the [Marmot Protocol](https://github.com/marmot-protocol/marmot) with MLS (Messaging Layer Security) and Nostr. The reference implementation is [White Noise](https://github.com/marmot-protocol/whitenoise).

## Architecture

```text
┌─────────────────────────────────────────────────────────────┐
│                    Flutter UI Layer                         │
│  (screens/, widgets/, providers/, services/)                │
├─────────────────────────────────────────────────────────────┤
│              Flutter-Rust Bridge Layer                      │
│  (lib/src/rust/ - auto-generated bindings — DO NOT EDIT)    │
├─────────────────────────────────────────────────────────────┤
│                    Rust API Layer                           │
│  (rust/src/api/ - thin wrapper around MDK + nostr-sdk)      │
├─────────────────────────────────────────────────────────────┤
│              MDK + nostr-sdk Rust Crates                    │
│  (external dependencies — core MLS + Nostr logic)           │
└─────────────────────────────────────────────────────────────┘
```

## Tech Stack

- **Flutter/Dart** — UI and application logic
- **Rust** — Core messaging/crypto via FFI
- **flutter_rust_bridge** — Dart ↔ Rust FFI bindings
- **Riverpod** — State management (shared state)
- **go_router** — Navigation/routing
- **MDK** — Marmot Development Kit (MLS groups, messages, invites)
- **nostr-sdk** — Nostr relay communication, event signing

## Directory Structure

```text
burrow/
├── app/                    # Flutter + Rust application
│   ├── lib/                # Flutter/Dart source code
│   │   ├── main.dart       # App entry point
│   │   ├── providers/      # Riverpod providers (shared state)
│   │   ├── services/       # Stateless operations (API call wrappers)
│   │   ├── screens/        # Full-page UI components
│   │   ├── widgets/        # Reusable components
│   │   └── src/rust/       # Auto-generated Rust bridge (DO NOT EDIT)
│   ├── rust/               # Rust source code
│   │   └── src/api/        # API modules exposed to Flutter
│   ├── android/            # Android platform config
│   ├── ios/                # iOS platform config
│   ├── linux/              # Linux platform config
│   ├── macos/              # macOS platform config
│   ├── windows/            # Windows platform config
│   └── web/                # Web platform config
├── src/                    # Phase 1 TypeScript CLI (legacy)
├── .github/workflows/      # CI configuration
└── AGENTS.md               # This file
```

## Issue Tracking

This project uses **bd** (beads) for issue tracking.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

## Development Commands

```bash
# Flutter
cd app
flutter pub get                     # Install dependencies
flutter analyze --no-fatal-infos    # Lint (must pass with 0 errors)
flutter test                        # Run tests
flutter build linux --release       # Build Linux
flutter build apk --debug           # Build Android APK (debug)
flutter build apk --release         # Build Android APK (release, needs keystore)

# Rust
cd app/rust
cargo check                         # Type-check
cargo fmt --check                   # Format check
cargo clippy --all-targets -- -D warnings  # Lint
cargo test --all-targets            # Run tests

# Regenerate FRB bindings (after changing Rust API)
cd app
flutter_rust_bridge_codegen generate
```

## Development Philosophy

Follow these principles (aligned with White Noise reference app):

1. **Simplicity over complexity** — keep the app thin
2. **Rust owns data** — all relay communication, caching, persistence in Rust
3. **No caching in Flutter** — the Rust layer handles profile/data caching
4. **Shared state in providers** — use Riverpod for app-wide state
5. **Screens watch providers** — screens observe providers, pass data down
6. **Delete dead code** — commented code is dead code
7. **Self-explanatory code** — avoid comments unless strictly necessary
8. **Test your code** — no untested code in PRs

## State Management Pattern

```text
Screen (watches providers)
    │
    ├── Providers (shared/persistent state)
    │   └── Auth, groups, relays, profiles, etc.
    │
    └── Services (stateless wrappers)
        └── UserService, etc. — thin wrappers around Rust API
```

## Profile Loading Pattern (from White Noise)

Profiles use a **two-step fetch** pattern:

1. **Non-blocking (cache):** `fetchProfile(pubkey, blockingSync: false)` — returns cached data immediately, may be empty.
2. **Blocking (relay):** Only if cache was empty, call `fetchProfile(pubkey, blockingSync: true)` — queries relays, waits up to 10s.

This avoids unnecessary network calls for known users while still resolving unknowns.

## Rust API Guidelines

- Modules in `rust/src/api/` are exposed to Flutter via FRB
- Functions use `#[frb]` attribute for bridge generation
- Structs use `#[frb(non_opaque)]` for Flutter compatibility
- Internal types use `#[frb(ignore)]` to hide from bridge
- Errors wrapped in `BurrowError` using `thiserror`
- Files in `lib/src/rust/` are auto-generated — **DO NOT EDIT manually**

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** — create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) — `flutter analyze`, builds
3. **Update issue status** — close finished work, update in-progress items
4. **PUSH TO REMOTE** — this is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** — clear stashes, prune remote branches
6. **Verify** — all changes committed AND pushed
7. **Hand off** — provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing — that leaves work stranded locally
- NEVER say "ready to push when you are" — YOU must push
- If push fails, resolve and retry until it succeeds
