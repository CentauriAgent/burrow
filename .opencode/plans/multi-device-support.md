# Burrow Multi-Device Support Plan

## Goal
Enable users to run Burrow on multiple devices (e.g., phone + laptop) under the same Nostr identity, with each device as a separate MLS leaf node that independently receives group invites and messages.

## Spec Reference
- **MIP-00 PR**: https://github.com/marmot-protocol/marmot/pull/40
- **MIP-00**: Added `client_id` tag to KeyPackage events (kind 443) + "Multi-Device Support" section
- **MIP-02**: Added "Multi-Device Considerations" section for Welcome delivery

## Architecture

```
Same nsec imported on both devices:

  ┌─────────────────────┐     ┌─────────────────────┐
  │  Device A (Android) │     │  Device B (Linux)    │
  │  client_id: 7f3a... │     │  client_id: b2c1... │
  │  Own MLS leaf node   │     │  Own MLS leaf node   │
  │  Own SQLite state    │     │  Own SQLite state    │
  │  Own KeyPackage      │     │  Own KeyPackage      │
  └──────────┬──────────┘     └──────────┬──────────┘
             │                           │
             ▼                           ▼
       Kind 443 event              Kind 443 event
       ["client_id","7f3a..."]     ["client_id","b2c1..."]
       Same author npub            Same author npub
             │                           │
             └───────────┬───────────────┘
                         ▼
                   Nostr Relays
                         │
                         ▼
              Alice queries for Bob's KPs
              Groups by client_id
              Selects newest per device
              Creates Welcome per device
```

## Design Decisions (from pika whiteboarding)

### client_id Tag (Option A — chosen over Kind 30443)

| | Option A: client_id tag | Option B: Kind 30443 |
|---|---|---|
| Spec change | One optional tag on existing kind | New event kind + d tag |
| Relay support | Works on every relay today | Needs parameterized replaceable support |
| Implementation | ~5 lines per client | Event kind migration |
| Provable in test | Trivial | Needs relay-side replacement logic |
| Upgrade path | Can later move to kind 30443 with d=client_id | N/A |

### Why client_id tag wins
1. **Smallest possible change** — one optional tag on existing Kind:443
2. **Deterministic** — grouping by client_id is always correct (vs "pick N most recent" which fails when one device refreshes more often)
3. **Backward compatible** — KPs without client_id treated as individual devices
4. **Natural upgrade path** — can move to kind 30443 with d=client_id later

### Privacy
- client_id is a random opaque value — reveals nothing about device type, OS, or hardware
- Does reveal that a given npub has N active devices, but this is already observable once those devices join a group (each is a visible leaf node)
- client_id MUST NOT be derived from nsec, hardware IDs, or any linkable value

---

## Phases

- [ ] Phase 1: Generate and persist client_id
- [ ] Phase 2: Publish client_id on KeyPackage events
- [ ] Phase 3: Fetch all KeyPackages per npub + selection algorithm
- [ ] Phase 4: Welcome delivery to multiple devices
- [ ] Phase 5: Test end-to-end multi-device flow
- [ ] Phase 6: Build and deploy

---

## Phase 1: Generate and Persist client_id

### Spec (from MIP-00 PR)
- MUST be 32-byte random value, hex-encoded to 64 characters
- MUST be generated once per client installation using a CSPRNG
- MUST be persisted locally and reused for all KeyPackage events
- MUST NOT be derived from user's Nostr identity key, device hardware identifiers, or any other linkable value
- Fresh client_id SHOULD be generated if user reinstalls or resets local MLS state

### Implementation

**File: `app/rust/src/api/state.rs`**
- On first initialization (when MLS state directory is created), generate 32 random bytes via `rand::thread_rng().gen::<[u8; 32]>()`, hex-encode
- Persist to a file alongside the MLS state (e.g., `<mls_dir>/client_id`)
- Load on subsequent launches
- Expose via FRB: `pub fn get_client_id() -> Result<String>`

**Dependencies to add:**
- `rand` crate (likely already present via MDK, but verify)

---

## Phase 2: Publish client_id on KeyPackage Events

### Spec (from MIP-00 PR)
- KeyPackage events SHOULD include: `["client_id", "<64-hex-char-random-id>"]`
- MDK's `create_key_package_for_event()` will accept an optional `client_id` parameter

### Implementation

**File: `app/rust/src/api/keypackage.rs`**

Current code (line 29-32):
```rust
let kp_data = s.mdk.create_key_package_for_event(&s.keys.public_key(), relays)?;
```

Change to:
```rust
let client_id = get_client_id()?;
let kp_data = s.mdk.create_key_package_for_event(&s.keys.public_key(), relays, Some(&client_id))?;
```

If MDK doesn't yet accept client_id (waiting on MDK release):
- Add the `["client_id", client_id]` tag manually to the event tags before publishing (lines 55-75)

**File: `app/lib/providers/auth_provider.dart`**
- No changes needed — `_publishKeyPackage()` calls Rust which now includes client_id automatically

---

## Phase 3: Fetch All KeyPackages + Selection Algorithm

### Spec (from MIP-00 PR)
Selection algorithm:
1. Query all kind:443 events for the target user's pubkey
2. Group the results by client_id tag value
3. Select the newest KeyPackage (highest created_at) from each group
4. Create a separate Add proposal and Welcome message for each selected KeyPackage

Backward compat: KPs without client_id tag treated as belonging to unique, unknown devices.

### Implementation

**File: `app/rust/src/api/invite.rs`**

Current code (lines 333-365) — THE CRITICAL FIX:
```rust
// CURRENT: fetches only ONE key package
let filter = Filter::new()
    .author(pubkey)
    .kind(Kind::MlsKeyPackage)
    .limit(1);  // <-- REMOVE THIS
```

Replace with:

1. Rename `fetch_key_package()` → `fetch_key_packages()` (return `Vec<String>`)
2. Remove `.limit(1)`
3. Port `select_one_kp_per_device()` from pika:

```rust
fn select_one_kp_per_device(kp_events: &[&Event]) -> Vec<&Event> {
    let mut by_device: BTreeMap<String, &Event> = BTreeMap::new();
    for event in kp_events {
        match get_client_id(event) {
            Some(id) => {
                let entry = by_device.entry(id).or_insert(event);
                if event.created_at > entry.created_at {
                    *entry = event;
                }
            }
            None => {
                // No client_id → treat as its own unique "device" (backward compat)
                by_device.insert(format!("__untagged_{}", event.id), event);
            }
        }
    }
    by_device.into_values().collect()
}

fn get_client_id(event: &Event) -> Option<String> {
    event.tags.iter()
        .find(|tag| tag.as_slice().first().map(|s| s.as_str()) == Some("client_id"))
        .and_then(|tag| tag.as_slice().get(1).map(|s| s.to_string()))
}
```

4. Updated `fetch_key_packages()` flow:
```rust
pub async fn fetch_key_packages(pubkey_hex: String) -> Result<Vec<String>> {
    let filter = Filter::new()
        .author(pubkey)
        .kind(Kind::MlsKeyPackage);  // No .limit(1)
    let events = client.fetch_events(vec![filter], timeout).await?;
    let event_refs: Vec<&Event> = events.iter().collect();
    let selected = select_one_kp_per_device(&event_refs);
    Ok(selected.iter().map(|e| e.as_json()).collect())
}
```

**File: `app/rust/src/api/invite.rs` (add_members)**

Current code (line 64) passes KP events to MDK:
```rust
s.mdk.add_members(&nostr_group_id, &kp_events)?;
```

MDK already accepts `&[Event]` — multiple KPs work. The critical change is upstream: passing ALL selected KPs instead of just one.

**Regenerate FRB bindings** after changing return type from `String` to `Vec<String>`.

---

## Phase 4: Welcome Delivery to Multiple Devices

### Spec (from MIP-02 PR addition)
- Inviter MUST create a separate Welcome for each of the user's devices (one per selected KeyPackage)
- Each Welcome references a specific KeyPackage via the `["e", <keypackage_event_id>]` tag
- Each device identifies its own Welcome by matching the e tag against KeyPackages it has published
- Devices MUST ignore Welcome messages referencing KeyPackages they did not create

### Implementation

**File: `app/lib/providers/invite_provider.dart`**

Current code (lines 46-67) maps 1:1 from KP author to welcome recipient:
```dart
final recipientPubkeys = keyPackageEventsJson.map((json) {
  final event = jsonDecode(json) as Map<String, dynamic>;
  return event['pubkey'] as String;
}).toList();
```

This already handles multiple KPs from the same npub correctly — the same recipient pubkey appears multiple times, and each welcome is gift-wrapped to that pubkey. Each device receives ALL welcomes for its npub, but only processes the one whose `e` tag matches a KP it published.

**Changes needed:**
- `fetchUserKeyPackage()` → `fetchUserKeyPackages()` — returns `List<String>` instead of `String`
- The invite flow collects all KPs from all invitees into a flat list before calling `addMembers()`

**File: `app/lib/screens/invite_members_screen.dart`**

Current code (lines 206-209) fetches one KP per invitee:
```dart
final kpJson = await fetchUserKeyPackage(pubkeyHex: hex);
keyPackageEventsJson.add(kpJson);
```

Change to:
```dart
final kpJsonList = await fetchUserKeyPackages(pubkeyHex: hex);
keyPackageEventsJson.addAll(kpJsonList);
```

The UI remains transparent — shows the user name, not device details.

**Welcome receiving (no changes needed):**
- `sync_welcomes()` in `invite.rs` already queries by p-tag for the current pubkey
- Each device independently processes welcomes addressed to it
- The `e` tag matching ensures a device only processes its own welcome
- MDK's `process_welcome()` is per-device — already correct

---

## Phase 5: Test End-to-End

### Test scenarios
1. **Two devices, same npub, both get invited to a group**
   - Import same nsec on Linux + Android
   - Both devices publish KPs with different client_ids
   - Third user creates group and invites the npub
   - Both devices receive and process their welcomes
   - Both devices see the same messages

2. **One device refreshes KP, invite still works**
   - Device A publishes a new KP (e.g., on app restart)
   - Inviter fetches KPs, groups by client_id, picks newest per device
   - Both devices still get invited correctly

3. **Backward compat: one device has client_id, one doesn't**
   - Old client publishes KP without client_id
   - New client publishes KP with client_id
   - Inviter treats untagged KP as unique device
   - Both devices get invited

4. **Single device (no regression)**
   - User with one device, one KP, one client_id
   - Invite flow works exactly as before

---

## Phase 6: Build and Deploy

- Run `flutter analyze --no-fatal-infos`
- Build Linux release
- Build Android release APK
- Install APK on phone
- Test with two physical devices

---

## Code Change Summary

### Files to modify

| # | File | Change | Lines affected |
|---|------|--------|----------------|
| 1 | `app/rust/src/api/state.rs` | Generate + persist + expose `client_id` | ~20 new lines |
| 2 | `app/rust/src/api/keypackage.rs` | Pass `client_id` to MDK / add tag to event | ~5 lines changed |
| 3 | `app/rust/src/api/invite.rs` | `fetch_key_packages()` returns `Vec<String>`, add `select_one_kp_per_device()` | ~40 lines changed/added |
| 4 | `app/lib/providers/invite_provider.dart` | `fetchUserKeyPackages()` returns `List<String>`, flatten into KP list | ~10 lines changed |
| 5 | `app/lib/screens/invite_members_screen.dart` | Call `fetchUserKeyPackages()`, `addAll()` results | ~3 lines changed |
| 6 | FRB regeneration | After Rust API changes | Auto-generated |

**Total: ~80 lines of meaningful changes across 5 files.**

### Files that already work (no changes needed)
- `app/rust/src/api/state.rs` — MLS state storage is per-device (separate SQLite)
- `app/rust/src/api/message.rs` — relay subscription uses h-tag, all devices receive
- `app/rust/src/api/group.rs` — `get_members()` returns deduplicated pubkeys
- `app/lib/providers/invite_provider.dart` — welcome receiving via `sync_welcomes()`
- `app/lib/screens/invite_members_screen.dart` — UI shows user names (transparent)
- `app/lib/main.dart` — no changes needed
- All call-related code — independent of multi-device

### Dependencies
- MDK update: `create_key_package_for_event()` with optional `client_id` param (if available)
- If MDK update not yet released, add client_id tag manually in Burrow

---

## What Already Works for Multi-Device (No Changes Needed)
- MLS state storage is per-device (separate SQLite databases per installation)
- Welcome receiving (`sync_welcomes`) queries by p-tag for pubkey — all devices with same key receive
- Message subscription uses h-tag on group's Nostr ID — all devices subscribed to relay get messages
- MDK's `add_members` accepts `&[Event]` with multiple KPs — supports multiple leaf nodes
- MDK's `process_message` and `process_welcome` are per-device operations
- Group member display (`get_members`) returns deduplicated pubkeys — shows "Bob" once
- DM detection (`is_dm = member_count == 2`) uses unique pubkeys from MDK, not leaf count

## Status
**Plan saved** — MIP-00/MIP-02 PR is open. Ready to implement once PR is merged or MDK is updated.
