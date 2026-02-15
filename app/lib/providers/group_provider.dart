import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/archive_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart';
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;
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

    // Publish the self-removal proposal to group relays (Marmot protocol).
    // leave_group creates a proposal (not a commit), so no merge_pending_commit.
    if (result.evolutionEventJson.isNotEmpty) {
      // Publish to group-specific relays first, fall back to broadcast
      try {
        final groupRelays = await getGroupRelays(mlsGroupIdHex: mlsGroupIdHex);
        for (final relay in groupRelays) {
          await rust_relay.publishEventJsonToRelay(
            eventJson: result.evolutionEventJson,
            relayUrl: relay,
          );
        }
      } catch (_) {
        // Fall back to broadcasting to all connected relays
        await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
      }
    }

    // Auto-archive the group so it's hidden from the main list
    await ref.read(archiveProvider.notifier).archive(mlsGroupIdHex);

    // Refresh group lists
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

  Future<UpdateGroupResult> updateDescription(
    String mlsGroupIdHex,
    String description,
  ) async {
    final result = await updateGroupDescription(
      mlsGroupIdHex: mlsGroupIdHex,
      description: description,
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
