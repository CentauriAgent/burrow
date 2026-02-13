import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
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

  /// Display name: prefer group name, fall back to peer name for unnamed DMs.
  String get displayName {
    // If the group has an explicit name, always use it
    if (name.isNotEmpty) return name;

    // For unnamed DMs, show peer display name or truncated pubkey
    if (isDirectMessage) {
      if (rustGroup.dmPeerDisplayName != null &&
          rustGroup.dmPeerDisplayName!.isNotEmpty) {
        return rustGroup.dmPeerDisplayName!;
      }
      if (dmPeerPubkeyHex != null) {
        return UserService.truncatePubkey(dmPeerPubkeyHex!);
      }
    }
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
      return rustGroups.map((g) => GroupInfo(rustGroup: g)).toList();
    } catch (_) {
      return [];
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
