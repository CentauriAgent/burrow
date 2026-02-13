import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/invite.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

class InviteNotifier extends AsyncNotifier<List<WelcomeInfo>> {
  @override
  Future<List<WelcomeInfo>> build() async {
    try {
      return await listPendingWelcomes();
    } catch (_) {
      return [];
    }
  }

  /// Full MIP-02 invite flow:
  /// 1. addMembers → get evolution event + welcome rumors
  /// 2. Publish evolution event (kind 445) to relays
  /// 3. Merge pending commit in MLS state
  /// 4. Gift-wrap each welcome rumor (kind 444) for its recipient
  /// 5. Publish gift-wrapped welcomes to relays
  Future<void> sendInvite({
    required String mlsGroupIdHex,
    required List<String> keyPackageEventsJson,
  }) async {
    // Clear any stale pending commit from a previous failed invite
    try {
      await rust_group.mergePendingCommit(mlsGroupIdHex: mlsGroupIdHex);
    } catch (_) {
      // No pending commit — that's fine
    }

    // 1. Create the MLS commit + welcome messages
    final result = await addMembers(
      mlsGroupIdHex: mlsGroupIdHex,
      keyPackageEventsJson: keyPackageEventsJson,
    );

    print(
      'DEBUG sendInvite: evolution=${result.evolutionEventJson.length}, welcomes=${result.welcomeRumorsJson.length}',
    );
    for (var j = 0; j < result.welcomeRumorsJson.length; j++) {
      print(
        'DEBUG sendInvite: welcome[$j] length=${result.welcomeRumorsJson[j].length}',
      );
    }

    // 2. Publish the evolution event (kind 445 commit) to relays
    if (result.evolutionEventJson.isNotEmpty) {
      print('DEBUG sendInvite: publishing evolution event (kind 445)');
      await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
      print('DEBUG sendInvite: evolution published OK');
    }

    // 3. Merge the pending commit in local MLS state
    await rust_group.mergePendingCommit(mlsGroupIdHex: mlsGroupIdHex);
    print('DEBUG sendInvite: pending commit merged');

    // 4. Gift-wrap and publish each welcome rumor
    // MDK welcome rumors don't have "p" tags — the recipient is the author
    // of the corresponding KeyPackage event. Welcome rumors are returned in
    // the same order as keyPackageEventsJson, so we correlate by index.
    final recipientPubkeys = keyPackageEventsJson.map((json) {
      final event = jsonDecode(json) as Map<String, dynamic>;
      return event['pubkey'] as String;
    }).toList();

    print('DEBUG sendInvite: recipientPubkeys=$recipientPubkeys');

    for (var i = 0; i < result.welcomeRumorsJson.length; i++) {
      final welcomeJson = result.welcomeRumorsJson[i];
      print(
        'DEBUG sendInvite: processing welcome[$i], empty=${welcomeJson.isEmpty}',
      );
      if (welcomeJson.isEmpty) continue;

      final recipientHex = i < recipientPubkeys.length
          ? recipientPubkeys[i]
          : null;
      print('DEBUG sendInvite: recipient[$i]=$recipientHex');
      if (recipientHex == null) continue;

      // Gift-wrap the welcome for this recipient (NIP-59)
      print('DEBUG sendInvite: gift-wrapping welcome for $recipientHex');
      final wrappedJson = await giftWrapWelcome(
        welcomeRumorJson: welcomeJson,
        recipientPubkeyHex: recipientHex,
      );
      print(
        'DEBUG sendInvite: gift-wrap done, wrappedJson length=${wrappedJson.length}',
      );

      // Dump the gift-wrapped event so we can verify p-tag and kind
      try {
        final wrapped = jsonDecode(wrappedJson) as Map<String, dynamic>;
        print(
          'DEBUG sendInvite: wrapped kind=${wrapped['kind']}, id=${wrapped['id']}',
        );
        final tags = wrapped['tags'] as List<dynamic>?;
        if (tags != null) {
          for (final tag in tags) {
            print('DEBUG sendInvite: wrapped tag=$tag');
          }
        }
      } catch (e) {
        print('DEBUG sendInvite: could not parse wrapped event: $e');
      }

      // Publish the gift-wrapped welcome to relays
      print('DEBUG sendInvite: publishing gift-wrapped welcome (kind 1059)');
      final publishResult = await rust_relay.publishEventJson(
        eventJson: wrappedJson,
      );
      print('DEBUG sendInvite: publishEventJson result=$publishResult');
      print(
        'DEBUG sendInvite: gift-wrapped welcome published OK for $recipientHex',
      );
    }

    print('DEBUG sendInvite: invite flow complete');
  }

  /// Fetch a user's key package from relays.
  Future<String> fetchUserKeyPackage(String pubkeyHex) async {
    return await fetchKeyPackage(pubkeyHex: pubkeyHex);
  }

  /// Accept a pending welcome.
  Future<void> acceptInvite(String welcomeEventIdHex) async {
    await acceptWelcome(welcomeEventIdHex: welcomeEventIdHex);
    state = AsyncData(await listPendingWelcomes());
  }

  /// Decline a pending welcome.
  Future<void> declineInvite(String welcomeEventIdHex) async {
    await declineWelcome(welcomeEventIdHex: welcomeEventIdHex);
    state = AsyncData(await listPendingWelcomes());
  }

  Future<void> refresh() async {
    state = AsyncData(await listPendingWelcomes());
  }
}

final inviteProvider = AsyncNotifierProvider<InviteNotifier, List<WelcomeInfo>>(
  () {
    return InviteNotifier();
  },
);

/// Count of pending invites for badge display.
final pendingInviteCountProvider = Provider<int>((ref) {
  final invites = ref.watch(inviteProvider);
  return invites.value?.where((w) => w.state == 'pending').length ?? 0;
});
