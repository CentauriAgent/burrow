import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/group.dart';
import 'package:burrow_app/providers/groups_provider.dart' as ui_groups;

class GroupNotifier extends AsyncNotifier<List<GroupInfo>> {
  @override
  Future<List<GroupInfo>> build() async {
    try {
      return await listGroups();
    } catch (_) {
      return [];
    }
  }

  Future<CreateGroupResult> createNewGroup({
    required String name,
    String description = '',
    required List<String> adminPubkeysHex,
    List<String> memberKeyPackageEventsJson = const [],
    required List<String> relayUrls,
  }) async {
    final result = await createGroup(
      name: name,
      description: description,
      adminPubkeysHex: adminPubkeysHex,
      memberKeyPackageEventsJson: memberKeyPackageEventsJson,
      relayUrls: relayUrls,
    );
    // Refresh group list
    state = AsyncData(await listGroups());
    return result;
  }

  Future<GroupInfo> getGroupInfo(String mlsGroupIdHex) async {
    return await getGroup(mlsGroupIdHex: mlsGroupIdHex);
  }

  Future<List<MemberInfo>> getMembers(String mlsGroupIdHex) async {
    return await getGroupMembers(mlsGroupIdHex: mlsGroupIdHex);
  }

  Future<UpdateGroupResult> leaveFromGroup(String mlsGroupIdHex) async {
    final result = await leaveGroup(mlsGroupIdHex: mlsGroupIdHex);
    // Remove from UI groups list immediately
    ref.read(ui_groups.groupsProvider.notifier).removeGroup(mlsGroupIdHex);
    state = AsyncData(await listGroups());
    return result;
  }

  Future<UpdateGroupResult> updateName(
    String mlsGroupIdHex,
    String name,
  ) async {
    final result = await updateGroupName(
      mlsGroupIdHex: mlsGroupIdHex,
      name: name,
    );
    state = AsyncData(await listGroups());
    return result;
  }

  Future<void> refresh() async {
    state = AsyncData(await listGroups());
  }
}

final groupProvider = AsyncNotifierProvider<GroupNotifier, List<GroupInfo>>(() {
  return GroupNotifier();
});
