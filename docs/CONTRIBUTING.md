# Contributing to Burrow

Thanks for your interest in Burrow! We welcome contributions from the Nostr and privacy communities.

## Getting Started

1. Fork the repo on GitHub
2. Clone your fork: `git clone https://github.com/<you>/burrow.git`
3. Create a branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Push and open a Pull Request

## Development Setup

See [BUILD.md](BUILD.md) for detailed build instructions.

```bash
# Quick start
cd burrow/app
flutter pub get
flutter_rust_bridge_codegen generate
flutter run -d linux  # or your platform
```

## Code Style

### Rust
- Run `cargo fmt` before committing
- Run `cargo clippy -- -D warnings` — no warnings allowed
- Follow standard Rust naming conventions

### Dart
- Run `flutter analyze` — no issues allowed
- Follow [Effective Dart](https://dart.dev/effective-dart) style guide
- Use `flutter_lints` (already configured)

### TypeScript (CLI)
- Strict mode enabled
- ESM modules (`"type": "module"`)

## Testing

### Before Submitting a PR

```bash
# Dart tests
cd app && flutter test

# Rust tests
cd app/rust && cargo test

# Dart analysis
cd app && flutter analyze

# Rust lints
cd app/rust && cargo clippy -- -D warnings
cd app/rust && cargo fmt --check
```

### Writing Tests
- Dart unit tests go in `app/test/`
- Rust unit tests go in `app/rust/tests/`
- Integration tests go in `app/integration_test/`
- Test new features. Test edge cases. Test error paths.

## Pull Request Guidelines

- **One feature per PR** — keep changes focused
- **Describe what and why** in the PR description
- **Reference issues** if applicable
- **Tests required** for new features and bug fixes
- **CI must pass** — fmt, clippy, analyze, test, cargo audit

## Branching

- `main` — stable, release-ready code
- `feature/*` — new features
- `fix/*` — bug fixes
- `docs/*` — documentation changes

## Issue Tracking

This project uses `bd` (beads) for issue tracking:

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress
bd close <id>
```

## Security Disclosures

**Do NOT open a public issue for security vulnerabilities.**

Instead:
1. Email the maintainer privately (see GitHub profile)
2. Include a detailed description of the vulnerability
3. Include steps to reproduce if possible
4. Allow reasonable time for a fix before public disclosure

See [SECURITY.md](../SECURITY.md) for the full security review and known issues.

## Architecture

Before making significant changes, review [ARCHITECTURE.md](../ARCHITECTURE.md) to understand the system design. Key points:

- **Rust handles all cryptography** — MLS, NIP-44, key management. Never add crypto to the Dart side.
- **MDK is the MLS engine** — Don't reimplement MLS operations; use MDK's API.
- **flutter_rust_bridge** generates FFI bindings — modify Rust API signatures, then run `flutter_rust_bridge_codegen generate`.
- **Riverpod** for state management — use providers, not ad-hoc state.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Questions? Open a discussion on GitHub or reach out on Nostr. 🦫
