import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Group info model (mirrors Rust GroupInfo FFI struct).
/// TODO: Replace with generated FFI binding when flutter_rust_bridge codegen runs.
class GroupInfo {
  final String mlsGroupIdHex;
  final String nostrGroupIdHex;
  final String name;
  final String description;
  final List<String> adminPubkeys;
  final int epoch;
  final String state;

  // UI-only fields (populated client-side)
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final int memberCount;

  // Direct message fields
  final bool isDirectMessage;
  final String? dmPeerPubkey; // hex pubkey of the other person in a 1:1 chat
  final String? dmPeerDisplayName; // npub or petname for display

  GroupInfo({
    required this.mlsGroupIdHex,
    required this.nostrGroupIdHex,
    required this.name,
    this.description = '',
    this.adminPubkeys = const [],
    this.epoch = 0,
    this.state = 'active',
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.memberCount = 0,
    this.isDirectMessage = false,
    this.dmPeerPubkey,
    this.dmPeerDisplayName,
  });

  /// Display name: for DMs show peer name, otherwise group name.
  String get displayName {
    if (isDirectMessage && dmPeerDisplayName != null && dmPeerDisplayName!.isNotEmpty) {
      return dmPeerDisplayName!;
    }
    return name;
  }
}

/// Groups list provider — fetches all groups for the current user.
class GroupsNotifier extends AsyncNotifier<List<GroupInfo>> {
  @override
  Future<List<GroupInfo>> build() async {
    // TODO: Call Rust FFI list_groups() when bindings are generated
    return [];
  }

  /// Refresh the groups list from the Rust backend.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }

  /// Add a newly created group to the local list.
  void addGroup(GroupInfo group) {
    final current = state.value ?? [];
    state = AsyncData([group, ...current]);
  }

  /// Remove a group from the local list (e.g. after leaving).
  void removeGroup(String mlsGroupIdHex) {
    final current = state.value ?? [];
    state = AsyncData(
      current.where((g) => g.mlsGroupIdHex != mlsGroupIdHex).toList(),
    );
  }
}

final groupsProvider =
    AsyncNotifierProvider<GroupsNotifier, List<GroupInfo>>(() {
  return GroupsNotifier();
});

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
