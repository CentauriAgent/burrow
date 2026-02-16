import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/providers/messages_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;
import 'package:burrow_app/services/user_service.dart';

/// Wrapper around Rust GroupInfo with UI-only fields.
class GroupInfo {
  final rust_group.GroupInfo rustGroup;

  // UI-only fields
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;

  GroupInfo({
    required this.rustGroup,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  String get mlsGroupIdHex => rustGroup.mlsGroupIdHex;
  String get nostrGroupIdHex => rustGroup.nostrGroupIdHex;
  String get name => rustGroup.name;
  String get description => rustGroup.description;
  List<String> get adminPubkeys => rustGroup.adminPubkeys;
  BigInt get epoch => rustGroup.epoch;
  String get state => rustGroup.state;
  int get memberCount => rustGroup.memberCount;
  bool get isDirectMessage => rustGroup.isDirectMessage;
  String? get dmPeerPubkeyHex => rustGroup.dmPeerPubkeyHex;

  /// Display name: for DMs, always prefer the peer's profile name.
  /// For group chats, use the group name.
  String get displayName {
    if (isDirectMessage) {
      // Always show the peer's name for DMs (like Signal)
      if (rustGroup.dmPeerDisplayName != null &&
          rustGroup.dmPeerDisplayName!.isNotEmpty) {
        return rustGroup.dmPeerDisplayName!;
      }
      if (dmPeerPubkeyHex != null) {
        return UserService.truncatePubkey(dmPeerPubkeyHex!);
      }
    }
    if (name.isNotEmpty) return name;
    return 'Unnamed Group';
  }

  /// DM peer profile picture URL (from Rust cache).
  String? get dmPeerPicture => rustGroup.dmPeerPicture;
}

/// Groups list provider — fetches all groups from the Rust backend.
class GroupsNotifier extends AsyncNotifier<List<GroupInfo>> {
  @override
  Future<List<GroupInfo>> build() async {
    try {
      final rustGroups = await rust_group.listGroups();
      final groups = rustGroups.map((g) => GroupInfo(rustGroup: g)).toList();
      // Resolve DM peer profiles in the background so names/avatars appear
      _resolveDmPeerProfiles(groups);
      return groups;
    } catch (_) {
      return [];
    }
  }

  /// Fetch profiles for DM peers whose names are not yet cached.
  /// Once fetched, the Rust profile cache is populated, so a refresh
  /// will pick up the names and pictures.
  Future<void> _resolveDmPeerProfiles(List<GroupInfo> groups) async {
    final pubkeysToResolve = <String>[];
    for (final g in groups) {
      if (g.isDirectMessage &&
          g.dmPeerPubkeyHex != null &&
          g.rustGroup.dmPeerDisplayName == null) {
        pubkeysToResolve.add(g.dmPeerPubkeyHex!);
      }
    }
    if (pubkeysToResolve.isEmpty) return;

    bool anyResolved = false;
    for (final hex in pubkeysToResolve) {
      try {
        final profile = await UserService(pubkeyHex: hex).fetchProfile();
        if (UserService.presentName(profile) != null) {
          anyResolved = true;
        }
      } catch (_) {}
    }
    // Refresh the list so the UI picks up the newly cached names/pictures
    if (anyResolved) {
      final updated = await rust_group.listGroups();
      state = AsyncData(updated.map((g) => GroupInfo(rustGroup: g)).toList());
    }
  }

  /// Refresh the groups list from the Rust backend.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  /// Remove a group from the local list (e.g. after leaving).
  void removeGroup(String mlsGroupIdHex) {
    final current = state.value ?? [];
    state = AsyncData(
      current.where((g) => g.mlsGroupIdHex != mlsGroupIdHex).toList(),
    );
  }

  Future<rust_group.CreateGroupResult> createNewGroup({
    required String name,
    String description = '',
    required List<String> adminPubkeysHex,
    List<String> memberKeyPackageEventsJson = const [],
    required List<String> relayUrls,
  }) async {
    final result = await rust_group.createGroup(
      name: name,
      description: description,
      adminPubkeysHex: adminPubkeysHex,
      memberKeyPackageEventsJson: memberKeyPackageEventsJson,
      relayUrls: relayUrls,
    );
    await refresh();
    // Restart message listener so the new group's messages are received
    ref.read(messageListenerProvider).restart();
    return result;
  }

  Future<rust_group.GroupInfo> getGroupInfo(String mlsGroupIdHex) async {
    return await rust_group.getGroup(mlsGroupIdHex: mlsGroupIdHex);
  }

  Future<List<rust_group.MemberInfo>> getMembers(String mlsGroupIdHex) async {
    return await rust_group.getGroupMembers(mlsGroupIdHex: mlsGroupIdHex);
  }

  Future<rust_group.UpdateGroupResult> leaveFromGroup(
    String mlsGroupIdHex,
  ) async {
    final result = await rust_group.leaveGroup(mlsGroupIdHex: mlsGroupIdHex);

    if (result.evolutionEventJson.isNotEmpty) {
      try {
        final groupRelays = await rust_group.getGroupRelays(
          mlsGroupIdHex: mlsGroupIdHex,
        );
        for (final relay in groupRelays) {
          await rust_relay.publishEventJsonToRelay(
            eventJson: result.evolutionEventJson,
            relayUrl: relay,
          );
        }
      } catch (_) {
        await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
      }
    }

    await ref.read(archiveProvider.notifier).archive(mlsGroupIdHex);
    removeGroup(mlsGroupIdHex);
    return result;
  }

  Future<rust_group.UpdateGroupResult> updateName(
    String mlsGroupIdHex,
    String name,
  ) async {
    final result = await rust_group.updateGroupName(
      mlsGroupIdHex: mlsGroupIdHex,
      name: name,
    );
    await refresh();
    return result;
  }

  Future<rust_group.UpdateGroupResult> updateDescription(
    String mlsGroupIdHex,
    String description,
  ) async {
    final result = await rust_group.updateGroupDescription(
      mlsGroupIdHex: mlsGroupIdHex,
      description: description,
    );
    await refresh();
    return result;
  }
}

final groupsProvider = AsyncNotifierProvider<GroupsNotifier, List<GroupInfo>>(
  () {
    return GroupsNotifier();
  },
);

/// Convenience: sorted groups by last message time (most recent first).
final sortedGroupsProvider = Provider<List<GroupInfo>>((ref) {
  final groups = ref.watch(groupsProvider).value ?? [];
  final sorted = List<GroupInfo>.from(groups);
  sorted.sort((a, b) {
    final aTime = a.lastMessageTime ?? DateTime(2000);
    final bTime = b.lastMessageTime ?? DateTime(2000);
    return bTime.compareTo(aTime);
  });
  return sorted;
});

/// Visible groups: active groups that are not archived.
/// This is what the main chat list should display.
final visibleGroupsProvider = Provider<List<GroupInfo>>((ref) {
  final groups = ref.watch(groupsProvider).value ?? [];
  final archived = ref.watch(archiveProvider);
  return groups
      .where(
        (g) => g.state != 'inactive' && !archived.contains(g.mlsGroupIdHex),
      )
      .toList();
});

/// Archived groups: groups explicitly archived by the user, plus inactive groups.
final archivedGroupsProvider = Provider<List<GroupInfo>>((ref) {
  final groups = ref.watch(groupsProvider).value ?? [];
  final archived = ref.watch(archiveProvider);
  return groups
      .where((g) => g.state == 'inactive' || archived.contains(g.mlsGroupIdHex))
      .toList();
});

/// Count of archived groups for badge display.
final archivedGroupCountProvider = Provider<int>((ref) {
  return ref.watch(archivedGroupsProvider).length;
});
