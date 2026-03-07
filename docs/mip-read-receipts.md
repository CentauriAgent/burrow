# MIP Read Receipts

> **Status:** Draft  
> **Author:** CentauriAgent  
> **Date:** 2026-03-07  
> **Depends on:** MIP-03 (Group Messages)

## Summary

Read receipts allow group members to signal that they have read (displayed) specific messages. Receipts are fully end-to-end encrypted using the existing MLS group encryption — relays see only opaque kind 445 events and learn nothing about who read what.

## Motivation

Read receipts are a core UX expectation in modern messaging apps. Users want to know whether their messages have been seen. Unlike centralized messengers, Burrow must deliver this feature without leaking metadata to relays or any third party.

## Design Principles

1. **E2EE by default** — Read receipts are MLS application messages. They travel inside the same kind 445 envelope as regular messages. Relays cannot distinguish a read receipt from a chat message.
2. **Batched** — A single receipt can acknowledge multiple messages at once, reducing bandwidth.
3. **Ephemeral-friendly** — Read receipts are transient signals. They update local state but do not need long-term storage. Implementations MAY discard receipt events after processing.
4. **Opt-out capable** — Users can disable sending read receipts in settings. Receiving and displaying receipts from others is always supported.

## Protocol

### Event Kind

Read receipts use **kind 15** inside the MLS-encrypted rumor. This is a custom Nostr kind chosen to avoid collision with existing NIPs.

The outer event on relays is always **kind 445** (MLS Group Message), identical to regular messages. The kind 15 is only visible after MLS + NIP-44 decryption.

### Rumor Format

```json
{
  "kind": 15,
  "content": "",
  "pubkey": "<reader-hex-pubkey>",
  "created_at": <unix-timestamp>,
  "tags": [
    ["e", "<message-event-id-1>"],
    ["e", "<message-event-id-2>"],
    ...
  ]
}
```

**Fields:**

| Field | Description |
|-------|-------------|
| `kind` | `15` — Read receipt |
| `content` | Empty string (no payload needed) |
| `pubkey` | Hex public key of the reader (set by MLS rumor builder) |
| `created_at` | Unix timestamp when the messages were read |
| `tags` | One or more `e` tags referencing the event IDs of read messages |

### Semantics

- An `e` tag in a read receipt means: "I (pubkey) have displayed this message (event ID) on my screen."
- A read receipt for message X implies all prior messages in the group were also read (monotonic). Implementations SHOULD track the latest read timestamp per member rather than per-message booleans.
- Multiple `e` tags allow batching — e.g., when a user opens a chat with 10 unread messages, one receipt covers all of them.

### Sending

A client SHOULD send a read receipt when:
1. The user opens a chat view containing unread messages.
2. New messages arrive while the chat view is already open.

A client SHOULD batch receipts with a short delay (e.g., 1-2 seconds) to coalesce multiple incoming messages into a single receipt event.

A client MUST NOT send receipts if the user has disabled them in settings.

### Receiving

When a client receives a kind 15 rumor:
1. Extract the reader's pubkey and the `e` tags.
2. For each referenced event ID, update the local read status: mark the message as "read by <pubkey>" at the receipt's `created_at` timestamp.
3. Update the UI (e.g., change single-check to double-check icon).

### Privacy

- **Relay-level:** Receipts are indistinguishable from regular MLS group messages on relays. No metadata leakage.
- **Group-level:** All group members can see who read which messages. This is the expected behavior for group messaging (same as Signal, WhatsApp).
- **Opt-out:** Users who disable read receipts simply stop *sending* kind 15 events. They still *receive* and display others' receipts.

## Data Model

### Read State (per message, per group member)

```
MessageReadState {
  event_id_hex: String,       // The message being tracked
  reader_pubkey_hex: String,  // Who read it
  read_at: u64,               // Unix timestamp of the receipt
}
```

### Aggregated View

For UI display, aggregate read states per message:
- **Sent** (single check ✓) — Message published to relay
- **Read** (double check ✓✓) — At least one other member sent a read receipt
- **Read by all** (blue double check ✓✓) — All group members (excluding sender) sent read receipts

## CLI Implementation

### New Command

```bash
burrow read-receipt <group-id> <message-id> [<message-id>...]
```

Sends a kind 15 MLS message with `e` tags for the specified message IDs.

### Daemon Processing

The daemon recognizes kind 15 rumors and logs them as `"type": "read_receipt"` entries:

```json
{
  "type": "read_receipt",
  "timestamp": "2026-03-07T10:30:00Z",
  "groupId": "abc123...",
  "senderPubkey": "def456...",
  "content": null,
  "messageIds": ["event1...", "event2..."]
}
```

### Storage

Read receipts are stored in `~/.burrow/read-receipts/<mls-group-id>/<reader-pubkey>.json`:

```json
{
  "reader_pubkey_hex": "def456...",
  "last_read_event_id": "event2...",
  "last_read_at": 1741350600,
  "read_event_ids": ["event1...", "event2..."]
}
```

## Flutter Implementation

### Message Model Extension

The `GroupMessage` struct gains an optional `readBy` field tracking which members have read the message:

```dart
class ReadReceipt {
  final String readerPubkeyHex;
  final int readAt;
  const ReadReceipt({required this.readerPubkeyHex, required this.readAt});
}
```

### UI Indicators

In `ChatBubble`, the existing `Icons.done_all` is replaced with dynamic status:

| State | Icon | Color |
|-------|------|-------|
| Sent | `Icons.done` (single check) | Grey |
| Read by some | `Icons.done_all` (double check) | Grey |
| Read by all | `Icons.done_all` (double check) | Blue/Primary |

### Provider

`MessagesNotifier` gains:
- `Map<String, List<ReadReceipt>> readReceipts` — indexed by message event ID
- `addReadReceipt(GroupMessage receipt)` — processes kind 15 messages
- `sendReadReceipt(List<String> eventIds)` — sends a batched receipt
- Auto-sends receipts when the chat view is open and new messages arrive

## Compatibility

- **WhiteNoise / other Marmot clients:** Kind 15 is a Burrow extension. Other clients will receive the MLS message but should ignore unknown kinds gracefully (per Nostr convention).
- **Backward compatibility:** Older Burrow versions will log kind 15 as an unknown message type. No breakage.

## Future Extensions

- **Delivery receipts** (kind 16): Signal that a message was received/decrypted (not necessarily displayed). Would show single check → delivered check → read check progression.
- **Per-recipient detail view:** Long-press a message to see exactly who read it and when (like WhatsApp's "Message Info").
- **Disappearing messages:** Read receipts could trigger auto-deletion timers.
