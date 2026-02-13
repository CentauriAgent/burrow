# Burrow Architecture

> Technical architecture of Burrow — a Marmot protocol (MLS + Nostr) encrypted messaging CLI.

## Overview

Burrow implements the [Marmot protocol](https://github.com/marmot-protocol) in TypeScript, combining the **Messaging Layer Security (MLS)** protocol (RFC 9420) with **Nostr** as a decentralized transport layer. The result is Signal-level end-to-end encryption without phone numbers, central servers, or identity providers.

### Design Philosophy

- **Nostr identity is the only identity** — A 32-byte keypair. No phone numbers, no email, no KYC.
- **Agent-native** — AI agents are first-class participants, not afterthoughts.
- **Protocol-first** — Strict compliance with Marmot MIPs ensures interoperability with other implementations (e.g., WhiteNoise).
- **Simple storage** — JSON files on disk. No database dependencies. Easy to inspect, backup, and migrate.
- **Minimal dependencies** — `ts-mls` for MLS, `nostr-tools` for Nostr, `@noble/*` for cryptography.

## Module Breakdown

```
src/
├── index.ts              # CLI entry point (Commander.js)
├── types/index.ts        # Protocol constants, interfaces, defaults
├── crypto/
│   ├── identity.ts       # Nostr keypair management (load/generate)
│   ├── nip44.ts          # NIP-44 encryption (group messages + gift-wrapping)
│   ├── utils.ts          # Hex/bytes conversion utilities
│   └── index.ts          # Re-exports
├── mls/
│   ├── keypackage.ts     # MLS KeyPackage generation (MIP-00)
│   ├── extensions.ts     # Marmot Group Data extension 0xF2EE (MIP-01)
│   ├── group.ts          # Group lifecycle: create, add member, send, receive
│   └── index.ts          # Re-exports
├── nostr/
│   ├── relay.ts          # Relay pool, event signing, ephemeral keys
│   ├── events.ts         # Event builders for kinds 443, 444, 445
│   └── index.ts          # Re-exports
├── store/index.ts        # File-based persistence (groups, keys, messages)
└── cli/
    ├── init.ts           # `burrow init` — identity + KeyPackage publishing
    ├── group.ts          # `burrow create-group` / `burrow groups`
    ├── invite.ts         # `burrow invite` — fetch KeyPackage, add member, send Welcome
    ├── send.ts           # `burrow send` — encrypt and publish group message
    ├── read.ts           # `burrow read` / `burrow listen` — decrypt and display
    └── index.ts          # Re-exports
```

### `types/` — Protocol Constants and Interfaces

Defines Marmot event kinds (`443`, `444`, `445`, `10051`), the Marmot extension ID (`0xF2EE`), and all data structures: `StoredGroup`, `StoredKeyPackage`, `GroupMessage`, `MarmotGroupData`, `BurrowConfig`. Also provides sensible defaults (relays, ciphersuite).

### `crypto/` — Identity and Encryption

- **`identity.ts`** — Loads Nostr secret keys from file (hex or nsec/bech32 format), derives x-only public keys via secp256k1/schnorr. Can generate new random identities.
- **`nip44.ts`** — Implements two encryption modes:
  - **Group messages (MIP-03):** Uses the MLS `exporter_secret` as both private key and public key derivation source for NIP-44 symmetric encryption.
  - **Gift-wrapping (MIP-02):** Standard NIP-44 between sender secret and recipient pubkey for Welcome events.

### `mls/` — MLS Protocol Operations

- **`keypackage.ts`** — Generates MLS KeyPackages per MIP-00. Includes Marmot-specific extensions (`0xF2EE`, `0x000A` last-resort) and uses `BasicCredential` with the raw 32-byte Nostr public key.
- **`extensions.ts`** — TLS presentation language serialization for the Marmot Group Data extension. Encodes/decodes: version, nostr_group_id (32 bytes), name, description, admin pubkeys, relays, and image metadata.
- **`group.ts`** — Full group lifecycle via `ts-mls`:
  - `createMarmotGroup()` — Creates MLS group with random IDs and Marmot extension
  - `addMember()` — Commits an Add proposal for a member's KeyPackage
  - `createGroupMsg()` — Creates MLS application messages (encrypted)
  - `processGroupMessage()` — Decodes and processes incoming MLS messages
  - `getExporterSecret()` — Derives the epoch's exporter secret for NIP-44 encryption
  - `serializeGroupState()` / `deserializeGroupState()` — Binary MLS state persistence

### `nostr/` — Relay Communication and Event Building

- **`relay.ts`** — Wraps `nostr-tools`' `SimplePool` for multi-relay publishing, subscription, and querying. Provides `createSignedEvent()` and `createEphemeralSignedEvent()` (random throwaway key).
- **`events.ts`** — Builds protocol-compliant Nostr events:
  - Kind `443` (KeyPackage) — base64 content, protocol version/ciphersuite/extension tags
  - Kind `444` (Welcome) — base64 MLS Welcome, unsigned, wrapped in NIP-59
  - Kind `445` (Group Message) — NIP-44 encrypted MLS ciphertext, published with ephemeral key
  - Kind `9` (inner chat) — unsigned application message inside MLS envelope

### `store/` — File-Based Persistence

`BurrowStore` manages `~/.burrow/` with subdirectories:
- `groups/` — JSON files keyed by `nostrGroupId`
- `keypackages/` — JSON files keyed by event ID
- `messages/` — Organized by group ID, sorted by timestamp
- `mls-state/` — Binary MLS `GroupState` blobs

### `cli/` — Command Handlers

Each CLI command maps to a function that orchestrates crypto → MLS → Nostr → store operations. Commands handle option parsing, user feedback, and error reporting.

## Data Flow: Sending a Message

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
│    { kind: 9, pubkey, content,  │  (NO signature — MIP-03)
│      created_at, tags }         │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 4. MLS encrypt (application     │  mls/group.ts
│    message via ts-mls)          │  → createApplicationMessage()
│    Output: MLS ciphertext bytes │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 5. NIP-44 encrypt using         │  crypto/nip44.ts
│    exporter_secret as key       │  (MIP-03 double encryption)
│    Output: NIP-44 ciphertext    │
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 6. Build kind 445 event with    │  nostr/events.ts
│    ephemeral keypair + h tag    │  (sender identity hidden)
└────────────────┬────────────────┘
                 ▼
┌─────────────────────────────────┐
│ 7. Publish to Nostr relays      │  nostr/relay.ts
│ 8. Save updated MLS state       │  store/index.ts
│ 9. Save message locally         │
└─────────────────────────────────┘
```

### Receiving a Message (Listen)

```
Nostr relay → kind 445 event with h tag matching group
                │
                ▼
1. Load MLS state for group
2. Get exporter_secret for current epoch
3. NIP-44 decrypt → MLS ciphertext
4. MLS processMessage() → plaintext bytes
5. Parse inner kind 9 JSON → sender pubkey + content
6. Display and store message
7. Save updated MLS state (epoch may advance)
```

## Key Management Lifecycle

```
┌─────────────────────────────────────────────────────┐
│                    INITIALIZATION                    │
│                                                     │
│  1. Load/generate Nostr keypair (secp256k1)         │
│  2. Generate MLS KeyPackage:                        │
│     - Credential: BasicCredential(raw 32-byte pubkey)│
│     - Ciphersuite: X25519 + AES-128-GCM + Ed25519  │
│     - Extensions: 0xF2EE (Marmot) + 0x000A (last-  │
│       resort)                                       │
│  3. Publish as kind 443 event to relays             │
│  4. Store KeyPackage + private key locally           │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                  GROUP CREATION                       │
│                                                     │
│  1. Generate random MLS group ID (32 bytes)          │
│  2. Generate random Nostr group ID (32 bytes)        │
│  3. Create MarmotGroupData extension (name, admins,  │
│     relays)                                         │
│  4. Initialize MLS group with creator's KeyPackage   │
│  5. Serialize and store GroupState                    │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│                  MEMBER ADDITION                      │
│                                                     │
│  1. Fetch invitee's kind 443 KeyPackage from relays  │
│  2. Decode MLS KeyPackage from event content          │
│  3. Create MLS Commit with Add proposal               │
│  4. Build kind 444 Welcome message                    │
│  5. NIP-44 encrypt Welcome for invitee               │
│  6. Gift-wrap (kind 1059) and publish                │
│  7. Epoch advances, new exporter_secret derived       │
└──────────────────────┬──────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────┐
│              ONGOING KEY RATCHETING                   │
│                                                     │
│  - Each Commit advances the epoch                    │
│  - New exporter_secret derived per epoch              │
│  - Forward secrecy: old keys can't decrypt new msgs  │
│  - Post-compromise security: key update heals after  │
│    compromise                                       │
└─────────────────────────────────────────────────────┘
```

## Marmot Protocol Compliance

### MIP-00: Key Packages

- ✅ Kind `443` events with base64-encoded MLS KeyPackage
- ✅ `mls_protocol_version`, `mls_ciphersuite`, `mls_extensions` tags
- ✅ `BasicCredential` with raw 32-byte Nostr public key
- ✅ Last-resort extension (`0x000A`)
- ✅ NIP-70 (`["-"]` tag) for author-only publishing

### MIP-01: Group Management

- ✅ Marmot Group Data extension (`0xF2EE`) with TLS serialization
- ✅ Fields: version, nostr_group_id, name, description, admin_pubkeys, relays, image metadata
- ✅ Group creation with extension embedded in MLS GroupContext
- ✅ `h` tag on group events references nostr_group_id

### MIP-02: Welcome Events

- ✅ Kind `444` Welcome events (unsigned inner event)
- ✅ NIP-59 gift-wrapping (kind 1059) for recipient privacy
- ✅ NIP-44 encryption between inviter and invitee
- ✅ References consumed KeyPackage event ID via `e` tag

### MIP-03: Group Messages

- ✅ Kind `445` events published with ephemeral keypair (sender anonymity)
- ✅ Double encryption: MLS application message → NIP-44 with exporter_secret
- ✅ Inner events are unsigned kind `9` (chat messages)
- ✅ Inner events do NOT include `h` tag (per spec)
- ✅ `h` tag on outer event for relay filtering

## Security Model

### Encryption Layers

| Layer | Protects | Mechanism |
|-------|----------|-----------|
| **MLS (inner)** | Message content, forward secrecy, post-compromise security | RFC 9420 via ts-mls |
| **NIP-44 (outer)** | MLS ciphertext from non-members observing relays | Exporter secret as symmetric key |
| **Ephemeral keys** | Sender identity on kind 445 events | Random keypair per message |
| **NIP-59 gift-wrap** | Welcome recipient identity | Encrypted kind 1059 wrapper |

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Relay operator reads messages | Double encryption (MLS + NIP-44) |
| Relay operator correlates sender/receiver | Ephemeral keys on group messages; gift-wrapping on Welcomes |
| Compromised member key | MLS post-compromise security via epoch ratcheting |
| Past message decryption after key compromise | MLS forward secrecy — old epoch keys are deleted |
| Metadata leakage (who is in a group) | `h` tag reveals group ID but not membership; KeyPackage publishing reveals existence |

### Trust Assumptions

- Nostr relays are **untrusted** — they transport encrypted blobs
- The MLS ciphersuite (`MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519`) provides 128-bit security
- `ts-mls` correctly implements RFC 9420 (audit status: community library, not yet formally audited)
- Secret keys are stored on disk with `0o600` permissions

## Dependencies

| Package | Purpose | Version |
|---------|---------|---------|
| `ts-mls` | MLS protocol (RFC 9420) implementation | ^1.6.1 |
| `nostr-tools` | Nostr event signing, relay management | ^2.23.1 |
| `@noble/curves` | secp256k1/schnorr for Nostr identity | ^2.0.1 |
| `@noble/hashes` | SHA-256, hex/bytes utilities | ^2.0.1 |
| `commander` | CLI framework | ^14.0.3 |

## Future Architecture Notes

- **Phase 2** (Flutter app) will use MDK (Rust) instead of ts-mls, connected via `flutter_rust_bridge`
- The CLI may migrate to MDK via NAPI-RS for full interoperability
- Both implementations target the same Marmot MIPs, ensuring cross-client compatibility
