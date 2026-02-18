# Tab Architecture Design — Chats + Contacts

## Overview

Add a two-tab interface (Chats / Contacts) to the left pane. On mobile, use `BottomNavigationBar`. On desktop (≥700px), use a `TabBar` under the AppBar inside the left pane. The existing `_ChatListPane` becomes the Chats tab content; a new `_ContactsListPane` becomes the Contacts tab content.

---

## Widget Tree

### Mobile (<700px)

```
ChatShellScreen (no initialGroupId)
└── Scaffold
    ├── AppBar (title: "Burrow", actions: [invites badge, profile avatar])
    ├── body: IndexedStack(index: _tabIndex)
    │   ├── [0] _ChatListBody(isWide: false)    ← extracted from current _ChatListPane.body
    │   └── [1] _ContactsListBody(isWide: false)
    ├── bottomNavigationBar: NavigationBar (M3)
    │   ├── NavigationDestination(icon: chat_bubble, label: "Chats")
    │   └── NavigationDestination(icon: contacts, label: "Contacts")
    └── floatingActionButton: _TabAwareFab(tabIndex)
        ├── tabIndex==0 → Icon(group_add), tooltip "Create Group", push /create-group
        └── tabIndex==1 → Icon(message), tooltip "New Message", push /new-dm
```

### Desktop (≥700px) — Left Pane

```
ChatShellScreen
└── Scaffold.body: Row
    ├── SizedBox(width: clampedWidth)  ← left pane
    │   └── Scaffold
    │       ├── AppBar
    │       │   ├── title: "Burrow"
    │       │   ├── actions: [invites badge, profile avatar]
    │       │   └── bottom: TabBar(tabs: ["Chats", "Contacts"])
    │       ├── body: TabBarView
    │       │   ├── [0] _ChatListBody(isWide: true)
    │       │   └── [1] _ContactsListBody(isWide: true)
    │       └── floatingActionButton: _TabAwareFab(tabIndex)
    ├── drag handle (unchanged)
    └── Expanded: _DetailPane (unchanged)
```

---

## State Management

### Tab Index

Use a local `_tabIndex` state variable inside `_ChatListPane` (renamed to `_LeftPane`). No provider needed — tab selection is ephemeral UI state.

- **Mobile:** `_LeftPane` becomes a `StatefulWidget`. Use `NavigationBar.onDestinationSelected` to set `_tabIndex`.
- **Desktop:** `_LeftPane` becomes a `StatefulWidget` with `SingleTickerProviderStateMixin` for `TabController`. Listen to `tabController.index` for FAB changes.

### Providers (no new providers needed)

| Provider | Used by | Notes |
|---|---|---|
| `contactsProvider` | `_ContactsListBody` | Already exists, returns `List<Contact>` sorted alphabetically |
| `groupProvider` / `visibleGroupsProvider` | `_ChatListBody` | Unchanged |
| `detailPaneProvider` | Desktop contact tap | Reuse `selectChat()` after finding/creating DM |
| `groupsProvider` | DM lookup | Check existing DMs before creating new one |

### Contact → DM Flow

When a contact is tapped:

1. Check `groupsProvider` for an existing DM with that `pubkeyHex` (match on `isDirectMessage && dmPeerPubkey == contact.pubkeyHex`)
2. If found → navigate to that group
3. If not found → create DM using same logic as `NewDmScreen._startDm()` (create group with `__dm__` description marker, refresh groups, navigate)

Extract the DM creation logic from `NewDmScreen` into a reusable function:

```dart
// lib/utils/dm_utils.dart
Future<String> findOrCreateDm(WidgetRef ref, String peerPubkeyHex) async {
  // Check existing groups for a DM with this peer
  final groups = ref.read(groupsProvider).value ?? [];
  for (final g in groups) {
    if (g.isDirectMessage && g.dmPeerPubkey == peerPubkeyHex) {
      return g.mlsGroupIdHex;
    }
  }
  // Create new DM (extracted from NewDmScreen)
  final auth = ref.read(authProvider).value!;
  final relayUrls = ref.read(relayProvider.notifier).defaultRelays;
  final short = peerPubkeyHex.length > 16
      ? '${peerPubkeyHex.substring(0, 8)}...${peerPubkeyHex.substring(peerPubkeyHex.length - 8)}'
      : peerPubkeyHex;
  final result = await ref.read(groupProvider.notifier).createNewGroup(
    name: 'DM-$short',
    description: '__dm__',
    adminPubkeysHex: [auth.account.pubkeyHex],
    relayUrls: relayUrls,
  );
  await ref.read(groupsProvider.notifier).refresh();
  return result.mlsGroupIdHex;
}
```

### Navigation on Contact Tap

**Mobile:**
```dart
onTap: () async {
  final groupId = await findOrCreateDm(ref, contact.pubkeyHex);
  context.go('/chat/$groupId');
}
```

**Desktop:**
```dart
onTap: () async {
  final groupId = await findOrCreateDm(ref, contact.pubkeyHex);
  ref.read(detailPaneProvider.notifier).selectChat(groupId);
}
```

---

## Contacts List Widget

```dart
class _ContactsListBody extends ConsumerWidget {
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    return contacts.when(
      data: (list) {
        if (list.isEmpty) return _EmptyContactsView();
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final contact = list[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundImage: contact.picture != null
                    ? NetworkImage(contact.picture!)
                    : null,
                child: contact.picture == null
                    ? Icon(Icons.person)
                    : null,
              ),
              title: Text(contact.name),
              subtitle: Text(_shortenKey(contact.pubkeyHex)),
              onTap: () async { /* findOrCreateDm + navigate */ },
            );
          },
        );
      },
      loading: () => Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
```

---

## File Changes

### New Files

| File | Purpose |
|---|---|
| `lib/utils/dm_utils.dart` | `findOrCreateDm()` extracted helper |
| `lib/widgets/contacts_list.dart` | `ContactsListBody` widget |
| `lib/widgets/tab_aware_fab.dart` | FAB that changes per tab index |

### Modified Files

| File | Changes |
|---|---|
| `lib/screens/chat_shell_screen.dart` | Refactor `_ChatListPane` → `_LeftPane` as StatefulWidget with tabs. Extract chat list body into `_ChatListBody`. Add TabBar (desktop) / NavigationBar (mobile). Wire up `_TabAwareFab`. |
| `lib/screens/new_dm_screen.dart` | Extract `_startDm` logic → call `findOrCreateDm()` instead. Keep screen for manual pubkey entry. |

### Unchanged Files

Everything else stays the same. Routes in `main.dart` are unchanged — `/new-dm` still exists for manual pubkey entry, contacts tab just provides a shortcut.

---

## Implementation Notes

1. **IndexedStack for mobile tabs** — keeps both tab states alive (no re-fetching contacts when switching back to Chats).

2. **TabBarView for desktop** — standard M3 pattern. Since the left pane has its own Scaffold, `TabBar` goes in `AppBar.bottom`.

3. **Loading state on contact tap** — show a brief `CircularProgressIndicator` overlay or disable the tile while `findOrCreateDm` runs (it may need to create a group). Use a local `_creatingDm` state in `_ContactsListBody` (make it stateful, track which pubkey is loading).

4. **No new routes needed** — contacts tab is internal to `ChatShellScreen`, not a separate route.

5. **Preserve archive swipe** — only on Chats tab. Contacts tab has no swipe actions.

6. **Online status** — `Contact` model doesn't currently have online status. For now, omit the green dot. Can be added later via a presence provider without changing this architecture. (If needed immediately, add an `isOnline` field to `Contact` and a `presenceProvider` — but that's a separate concern.)
