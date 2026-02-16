/// Legacy group provider — delegates to [groupsProvider] for all operations.
/// Kept for backward compatibility; new code should use [groupsProvider] directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/groups_provider.dart' as ui;
import 'package:burrow_app/src/rust/api/group.dart';

class GroupNotifier extends AsyncNotifier<List<GroupInfo>> {
  @override
  Future<List<GroupInfo>> build() async {
    // Watch groupsProvider so this stays in sync automatically
    final groups = ref.watch(ui.groupsProvider).value ?? [];
    return groups.map((g) => g.rustGroup).toList();
  }

  Future<CreateGroupResult> createNewGroup({
    required String name,
    String description = '',
    required List<String> adminPubkeysHex,
    List<String> memberKeyPackageEventsJson = const [],
    required List<String> relayUrls,
  }) async {
    return ref
        .read(ui.groupsProvider.notifier)
        .createNewGroup(
          name: name,
          description: description,
          adminPubkeysHex: adminPubkeysHex,
          memberKeyPackageEventsJson: memberKeyPackageEventsJson,
          relayUrls: relayUrls,
        );
  }

  Future<GroupInfo> getGroupInfo(String mlsGroupIdHex) async {
    return ref.read(ui.groupsProvider.notifier).getGroupInfo(mlsGroupIdHex);
  }

  Future<List<MemberInfo>> getMembers(String mlsGroupIdHex) async {
    return ref.read(ui.groupsProvider.notifier).getMembers(mlsGroupIdHex);
  }

  Future<UpdateGroupResult> leaveFromGroup(String mlsGroupIdHex) async {
    return ref.read(ui.groupsProvider.notifier).leaveFromGroup(mlsGroupIdHex);
  }

  Future<UpdateGroupResult> updateName(
    String mlsGroupIdHex,
    String name,
  ) async {
    return ref.read(ui.groupsProvider.notifier).updateName(mlsGroupIdHex, name);
  }

  Future<UpdateGroupResult> updateDescription(
    String mlsGroupIdHex,
    String description,
  ) async {
    return ref
        .read(ui.groupsProvider.notifier)
        .updateDescription(mlsGroupIdHex, description);
  }

  Future<void> refresh() async {
    await ref.read(ui.groupsProvider.notifier).refresh();
  }
}

final groupProvider = AsyncNotifierProvider<GroupNotifier, List<GroupInfo>>(() {
  return GroupNotifier();
});
