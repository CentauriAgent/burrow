# Unread Badges, Message Previews & Read State

## Goal
Show Signal-style unread count badges and last message previews in the sidebar. Persist all read/archive state in Rust-side SQLite alongside MLS data.

## Current State
- `ChatListTile` UI is fully built: unread badge, bold text, last message preview, timestamp formatting
- `GroupInfo` wrapper has `unreadCount`, `lastMessage`, `lastMessageTime` fields — always 0/null
- `shared_preferences` stores archived group IDs (to be migrated)
- MDK stores messages in SQLite with pagination support
- No read pointer or unread tracking exists anywhere

## Architecture Decision
**Rust-side SQLite** for all state (not shared_preferences). Reasons:
- Follows "Rust owns data" principle (AGENTS.md)
- Atomic with MLS state — backup/restore includes read markers
- Ready for multi-device sync via Nostr events
- Single source of truth, no cross-layer inconsistency
- Migrate existing archive state from shared_preferences

## Phases

- [ ] Phase 1: Rust-side app state SQLite table
- [ ] Phase 2: Populate last message + unread count
- [ ] Phase 3: Active group tracker + mark-as-read
- [ ] Phase 4: Real-time updates from message listener
- [ ] Phase 5: Migrate archive state from shared_preferences
- [ ] Phase 6: Build and test

---

## Phase 1: Rust-Side App State SQLite Table

### New table in the MLS SQLite database

```sql
CREATE TABLE IF NOT EXISTS app_state (
    group_id_hex TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (group_id_hex, key)
);
```

Key-value per group. Keys:
- `last_read_event_id` — hex event ID of the last message the user has seen
- `last_read_timestamp` — unix timestamp of that message (for efficient unread counting)
- `archived` — "true" if group is archived
- `muted` — "true" if group is muted (future use)

### New Rust API functions (`app/rust/src/api/app_state.rs`)

```rust
/// Store a key-value pair for a group in the app state table.
pub async fn set_group_state(group_id_hex: String, key: String, value: String) -> Result<(), BurrowError>

/// Get a value for a group from the app state table.
pub async fn get_group_state(group_id_hex: String, key: String) -> Result<Option<String>, BurrowError>

/// Delete a key-value pair for a group.
pub async fn delete_group_state(group_id_hex: String, key: String) -> Result<(), BurrowError>

/// Get all archived group IDs.
pub async fn get_archived_groups() -> Result<Vec<String>, BurrowError>

/// Mark a group as read (store last seen event ID and timestamp).
pub async fn mark_group_read(group_id_hex: String, last_event_id_hex: String, timestamp: i64) -> Result<(), BurrowError>

/// Get the last-read event ID for a group.
pub async fn get_last_read_event_id(group_id_hex: String) -> Result<Option<String>, BurrowError>
```

### SQLite access
The MLS database path is already known (`<data_dir>/mls/<pubkey_hex>/`). Open the same database file or a sibling `app_state.db` in the same directory. Using the same file is simpler — just add the table with `CREATE TABLE IF NOT EXISTS` during initialization.

**File changes:**
- New file: `app/rust/src/api/app_state.rs` (~100 lines)
- Modified: `app/rust/src/api/mod.rs` (register new module)
- Modified: `app/rust/src/api/state.rs` (add SQLite connection to BurrowState, create table on init)
- Regenerate FRB bindings

---

## Phase 2: Populate Last Message + Unread Count

### New Rust helper: get group summary

```rust
/// Get last message + unread count for a group.
pub async fn get_group_summary(mls_group_id_hex: String) -> Result<GroupSummary, BurrowError>

#[frb(non_opaque)]
pub struct GroupSummary {
    pub last_message_content: Option<String>,
    pub last_message_timestamp: Option<i64>,
    pub last_message_author_hex: Option<String>,
    pub unread_count: u32,
}
```

Implementation:
1. Call `mdk.get_messages(&group_id, Pagination { limit: 1, offset: 0 })` for last message
2. Get `last_read_timestamp` from app_state table
3. Count messages with `created_at > last_read_timestamp` for unread count
   - MDK's `get_messages()` only supports limit/offset, not timestamp filtering
   - Option A: Iterate messages until we hit one older than last_read (simple, fine for small counts)
   - Option B: Direct SQL query on MDK's messages table (faster, but couples to MDK schema)
   - **Choose Option A for now** — iterate with small pages until past the read pointer

### Dart changes: enrich GroupInfo on load

**File: `app/lib/providers/groups_provider.dart`**

In `build()` and `refresh()`, after loading groups from Rust:
```dart
for (final group in groups) {
  final summary = await rust_app_state.getGroupSummary(
    mlsGroupIdHex: group.mlsGroupIdHex,
  );
  // Construct GroupInfo with real values
}
```

This populates `lastMessage`, `lastMessageTime`, and `unreadCount` with real data.

**File changes:**
- New: `app/rust/src/api/app_state.rs` (add `get_group_summary`)
- Modified: `app/lib/providers/groups_provider.dart` (enrich GroupInfo)
- Regenerate FRB

---

## Phase 3: Active Group Tracker + Mark-as-Read

### Active group provider

**File: `app/lib/providers/groups_provider.dart`** (or new file)

```dart
/// Tracks which group the user is currently viewing.
final activeGroupProvider = StateProvider<String?>((ref) => null);
```

### Set active group when viewing

**File: `app/lib/screens/chat_view_screen.dart`**

On `initState()` (replacing the TODO at line 39):
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  ref.read(activeGroupProvider.notifier).state = widget.groupId;
  // Mark all messages as read
  _markAsRead();
});
```

`_markAsRead()`:
1. Get the newest message from `messagesProvider(groupId).messages.first`
2. Call `rust_app_state.markGroupRead(groupId, eventId, timestamp)`
3. Update the group's `unreadCount` to 0 in the provider

### Clear active group on leave

When navigating away from a chat, set `activeGroupProvider` to null.

**File changes:**
- Modified: `app/lib/screens/chat_view_screen.dart` (set active group, mark as read)
- Modified: `app/lib/providers/groups_provider.dart` (add activeGroupProvider)
- New Rust API: `mark_group_read()` in `app_state.rs`

---

## Phase 4: Real-Time Updates from Message Listener

### Update group list when messages arrive

**File: `app/lib/providers/messages_provider.dart`**

In the `MessageListener` stream handler (line 221-225), after dispatching to `messagesProvider`:

```dart
if (notification.notificationType == 'application_message' &&
    notification.message != null) {
  // Dispatch to per-group messages
  _ref.read(messagesProvider(notification.mlsGroupIdHex).notifier)
      .addIncomingMessage(notification.message!);

  // Update group list: last message preview + unread count
  final activeGroup = _ref.read(activeGroupProvider);
  final isActive = activeGroup == notification.mlsGroupIdHex;

  _ref.read(groupsProvider.notifier).updateGroupPreview(
    groupId: notification.mlsGroupIdHex,
    lastMessage: notification.message!.content,
    lastMessageTime: DateTime.fromMillisecondsSinceEpoch(
      notification.message!.createdAt * 1000,
    ),
    incrementUnread: !isActive,
  );

  // If this is the active chat, immediately mark as read
  if (isActive) {
    rust_app_state.markGroupRead(
      mlsGroupIdHex: notification.mlsGroupIdHex,
      lastEventIdHex: notification.message!.eventIdHex,
      timestamp: notification.message!.createdAt,
    );
  }
}
```

### New method on GroupsNotifier

```dart
void updateGroupPreview({
  required String groupId,
  required String lastMessage,
  required DateTime lastMessageTime,
  required bool incrementUnread,
}) {
  final current = state.value ?? [];
  state = AsyncData(current.map((g) {
    if (g.mlsGroupIdHex != groupId) return g;
    return GroupInfo(
      rustGroup: g.rustGroup,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: incrementUnread ? g.unreadCount + 1 : 0,
    );
  }).toList());
}
```

**File changes:**
- Modified: `app/lib/providers/messages_provider.dart` (update group preview on message)
- Modified: `app/lib/providers/groups_provider.dart` (add `updateGroupPreview`, `activeGroupProvider`)

---

## Phase 5: Migrate Archive State from shared_preferences

### Move archive to Rust-side SQLite

**File: `app/lib/providers/archive_provider.dart`**

Replace `SharedPreferences` calls with Rust API calls:
- `archive(groupId)` → `set_group_state(groupId, 'archived', 'true')`
- `unarchive(groupId)` → `delete_group_state(groupId, 'archived')`
- `isArchived(groupId)` → `get_group_state(groupId, 'archived') == 'true'`
- `loadArchived()` → `get_archived_groups()`

### Migration on first run

In `archive_provider.dart` `build()`:
1. Check if `shared_preferences` has `'archived_group_ids'`
2. If yes, migrate each to Rust-side SQLite
3. Delete the shared_preferences key
4. Going forward, only use Rust API

**File changes:**
- Modified: `app/lib/providers/archive_provider.dart` (replace SharedPreferences with Rust API)
- May remove `shared_preferences` from `pubspec.yaml` if no other users

---

## Phase 6: Build and Test

- Regenerate FRB bindings: `flutter_rust_bridge_codegen generate`
- Run `cargo check`, `cargo clippy`, `flutter analyze`
- Build Linux + Android
- Test scenarios:
  - New message in inactive chat → badge appears
  - Open chat → badge disappears
  - App restart → badges persist
  - Archive/unarchive → works from Rust storage
  - Last message preview shows in sidebar
  - Groups sorted by most recent message

---

## Code Change Summary

### New files
| File | Lines (est.) | Purpose |
|------|------|---------|
| `app/rust/src/api/app_state.rs` | ~200 | SQLite app state table + all CRUD operations + group summary |

### Modified files
| File | Change |
|------|--------|
| `app/rust/src/api/mod.rs` | Register `app_state` module |
| `app/rust/src/api/state.rs` | Add SQLite connection, create table on init |
| `app/lib/providers/groups_provider.dart` | Enrich GroupInfo with real data, add `updateGroupPreview`, `activeGroupProvider` |
| `app/lib/providers/messages_provider.dart` | Update group preview on incoming message |
| `app/lib/screens/chat_view_screen.dart` | Set active group, mark as read on view |
| `app/lib/providers/archive_provider.dart` | Migrate from SharedPreferences to Rust API |
| FRB auto-generated files | Regenerated |

### Estimated total: ~350 lines new code, ~100 lines modified

## Status
**Plan saved** — ready to implement.
