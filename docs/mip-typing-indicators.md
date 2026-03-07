# MIP Typing Indicators

> **Status:** Implemented  
> **Author:** CentauriAgent  
> **Date:** 2026-03-07  
> **Depends on:** MIP-03 (Group Messages)

## Summary

Typing indicators allow group members to see when others are actively composing a message. Indicators are MLS-encrypted (kind 10000 inside the MLS envelope) so relays learn nothing about who is typing to whom.

## Motivation

"X is typing..." is a core UX expectation in modern messaging. It creates a sense of presence and liveness in conversations. Typing indicators are lightweight, ephemeral signals — they don't need persistence or delivery guarantees.

## Design Decision: MLS-Encrypted vs Ephemeral Nostr Events

Three approaches were considered:

### Option A: Ephemeral Nostr Events (kind 20000-29999)
- **Pros:** No MLS overhead, relays don't store them (NIP-16)
- **Cons:** Leaks metadata (who is typing to whom visible to relays), requires separate subscription management, no group-level privacy

### Option B: Direct Relay Messages (NIP-17 DM-style)
- **Pros:** Simple
- **Cons:** Only works for 1:1, not groups; still leaks metadata

### Option C: MLS-Encrypted Application Messages ✅ (Chosen)
- **Pros:** Full E2EE, consistent with Burrow's message pipeline, works for groups of any size, no metadata leakage
- **Cons:** Slightly more overhead than plain ephemeral events

**Decision:** Option C. Consistency with the existing MLS pipeline outweighs the minor overhead. Typing indicators travel as kind 445 events on the wire — relays cannot distinguish them from real messages. The inner rumor uses kind 10000 (ephemeral indicator), which recipients filter and surface as transient UI state.

## Protocol

### Inner Event Kind

Typing indicators use **kind 10000** inside the MLS-encrypted rumor. This kind number follows Nostr's ephemeral event range (10000-19999) semantically, even though the outer envelope is kind 445.

### Rumor Format

```json
{
  "kind": 10000,
  "content": "typing",
  "pubkey": "<sender-hex-pubkey>",
  "created_at": <unix-timestamp>,
  "tags": []
}
```

| Field | Description |
|-------|-------------|
| `kind` | `10000` — Typing indicator |
| `content` | `"typing"` — Fixed string (future: could be `"stopped"`) |
| `pubkey` | Hex public key of the person typing |
| `created_at` | Unix timestamp |
| `tags` | Empty (no references needed) |

### Sender Behavior

1. When the user begins typing in a group chat, send a typing indicator.
2. **Debounce:** After sending, suppress additional indicators for **3 seconds** (avoid flooding).
3. **Stop signal:** When a message is sent, the typing indicator naturally clears on the receiver side (see below). No explicit "stopped typing" event is needed.
4. If the user stops typing without sending (clears input, navigates away), the indicator expires naturally on the receiver side.

### Receiver Behavior

1. On receiving a kind 10000 message, record the sender's pubkey with an expiration timestamp of **now + 5 seconds**.
2. Display "X is typing..." in the chat UI for all non-expired typing states.
3. Run a periodic cleanup timer (every 2 seconds) to remove expired typing states.
4. When a regular message arrives from a sender, **immediately clear** their typing state (they finished typing).
5. Never store typing indicators in message history — they are purely transient.

### Expiry & Resilience

- **5-second expiry** handles disconnects gracefully: if a user closes the app mid-typing, the indicator disappears within 5 seconds.
- **3-second debounce** limits typing indicators to ~1 every 3 seconds per user, keeping bandwidth low.
- Typing indicators are **fire-and-forget**: failures are silently ignored.

## Implementation

### Rust (`api/message.rs`)

- `send_typing_indicator(mls_group_id_hex)` — Creates a kind 10000 rumor, MLS-encrypts it, returns kind 445 event JSON.
- Constant: `TYPING_INDICATOR_KIND = 10000`

### Flutter Provider (`providers/messages_provider.dart`)

- `TypingState` class: tracks `pubkeyHex` and `expiresAt`
- `MessagesNotifier._typingUsers`: Map of currently typing users
- `MessagesNotifier.onTyping()`: Debounced sender-side trigger (3s cooldown)
- `MessagesNotifier.addIncomingMessage()`: Intercepts kind 10000, updates typing state, clears typing on regular message receipt
- `MessagesNotifier.typingPubkeys`: Getter that filters expired states

### Flutter Widget (`widgets/typing_indicator.dart`)

- `TypingIndicator`: Reusable widget with animated bouncing dots
- Resolves pubkeys to display names via profile providers
- Handles singular ("X is typing...") and plural ("X, Y are typing...")

### Integration (`screens/chat_view_screen.dart`)

- `TypingIndicator` widget placed between mention suggestions and the input bar
- `onChanged` callback on the text field triggers `onTyping()`

## Security Considerations

- **No metadata leakage:** Typing indicators are MLS-encrypted. Relays see only standard kind 445 events.
- **Forward secrecy:** Covered by MLS epoch rotation like all other messages.
- **Privacy trade-off:** Group members can see when you're typing. Future: add a per-user "disable typing indicators" setting.

## Future Enhancements

- **Opt-out setting:** Allow users to disable sending typing indicators
- **Stop signal:** Explicit "stopped typing" event for instant clearing
- **Audio/video recording indicator:** "X is recording a voice message..."
