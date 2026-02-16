import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/messages_provider.dart';
import 'package:burrow_app/src/rust/api/invite.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

class InviteNotifier extends AsyncNotifier<List<WelcomeInfo>> {
  @override
  Future<List<WelcomeInfo>> build() async {
    // Sync welcomes from relays, then list from MDK storage
    try {
      await syncWelcomes();
    } catch (_) {}
    try {
      return await listPendingWelcomes();
    } catch (_) {
      return [];
    }
  }

  /// Full MIP-02 invite flow.
  Future<void> sendInvite({
    required String mlsGroupIdHex,
    required List<String> keyPackageEventsJson,
  }) async {
    // Clear any stale pending commit
    try {
      await rust_group.mergePendingCommit(mlsGroupIdHex: mlsGroupIdHex);
    } catch (_) {}

    // 1. Create the MLS commit + welcome messages
    final result = await addMembers(
      mlsGroupIdHex: mlsGroupIdHex,
      keyPackageEventsJson: keyPackageEventsJson,
    );

    // 2. Publish the evolution event (kind 445 commit) to relays
    if (result.evolutionEventJson.isNotEmpty) {
      await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
    }

    // 3. Merge the pending commit in local MLS state
    await rust_group.mergePendingCommit(mlsGroupIdHex: mlsGroupIdHex);

    // 4. Gift-wrap and publish each welcome rumor
    final recipientPubkeys = keyPackageEventsJson.map((json) {
      final event = jsonDecode(json) as Map<String, dynamic>;
      return event['pubkey'] as String;
    }).toList();

    for (var i = 0; i < result.welcomeRumorsJson.length; i++) {
      final welcomeJson = result.welcomeRumorsJson[i];
      if (welcomeJson.isEmpty) continue;

      final recipientHex = i < recipientPubkeys.length
          ? recipientPubkeys[i]
          : null;
      if (recipientHex == null) continue;

      final wrappedJson = await giftWrapWelcome(
        welcomeRumorJson: welcomeJson,
        recipientPubkeyHex: recipientHex,
      );

      await rust_relay.publishEventJson(eventJson: wrappedJson);
    }
  }

  Future<String> fetchUserKeyPackage(String pubkeyHex) async {
    return await fetchKeyPackage(pubkeyHex: pubkeyHex);
  }

  Future<void> acceptInvite(String welcomeEventIdHex) async {
    await acceptWelcome(welcomeEventIdHex: welcomeEventIdHex);
    state = AsyncData(await listPendingWelcomes());
    // Refresh group list so sidebar shows the new group
    ref.read(groupsProvider.notifier).refresh();
    // Restart message listener so the new group's messages are received
    ref.read(messageListenerProvider).restart();
  }

  Future<void> declineInvite(String welcomeEventIdHex) async {
    await declineWelcome(welcomeEventIdHex: welcomeEventIdHex);
    state = AsyncData(await listPendingWelcomes());
  }

  Future<void> refresh() async {
    try {
      await syncWelcomes();
    } catch (_) {}
    state = AsyncData(await listPendingWelcomes());
  }
}

final inviteProvider = AsyncNotifierProvider<InviteNotifier, List<WelcomeInfo>>(
  () => InviteNotifier(),
);

/// Count of pending invites for badge display.
final pendingInviteCountProvider = Provider<int>((ref) {
  final invites = ref.watch(inviteProvider);
  return invites.value?.where((w) => w.state == 'pending').length ?? 0;
});
