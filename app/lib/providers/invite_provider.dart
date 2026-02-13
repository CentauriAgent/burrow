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
    for (final welcomeJson in result.welcomeRumorsJson) {
      if (welcomeJson.isEmpty) continue;

      // Extract recipient pubkey from the welcome rumor's "p" tag
      final recipientHex = _extractRecipientPubkey(welcomeJson);
      if (recipientHex == null) continue;

      // Gift-wrap the welcome for this recipient (NIP-59)
      final wrappedJson = await giftWrapWelcome(
        welcomeRumorJson: welcomeJson,
        recipientPubkeyHex: recipientHex,
      );

      // Publish the gift-wrapped welcome to relays
      await rust_relay.publishEventJson(eventJson: wrappedJson);
    }
  }

  /// Extract the recipient pubkey hex from a welcome rumor JSON's "p" tag.
  String? _extractRecipientPubkey(String rumorJson) {
    try {
      final map = jsonDecode(rumorJson) as Map<String, dynamic>;
      final tags = map['tags'] as List<dynamic>?;
      if (tags == null) return null;
      for (final tag in tags) {
        final t = tag as List<dynamic>;
        if (t.isNotEmpty && t[0] == 'p' && t.length >= 2) {
          return t[1] as String;
        }
      }
    } catch (_) {}
    return null;
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
