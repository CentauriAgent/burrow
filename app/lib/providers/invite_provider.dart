import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/api/invite.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

class InviteNotifier extends AsyncNotifier<List<WelcomeInfo>> {
  Future<void> _log(String msg) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/invite_debug.log');
    final ts = DateTime.now().toIso8601String();
    await file.writeAsString('[$ts] $msg\n', mode: FileMode.append);
  }

  @override
  Future<List<WelcomeInfo>> build() async {
    // Sync welcomes from relays before listing
    try {
      // Log connected relays first
      try {
        final relays = await rust_relay.listRelays();
        final connected = relays.where((r) => r.connected).toList();
        await _log(
          'connected relays: ${connected.length}/${relays.length} - ${connected.map((r) => r.url).join(', ')}',
        );
      } catch (_) {}
      await _log('calling syncWelcomes...');
      final count = await syncWelcomes();
      await _log('syncWelcomes found $count new welcomes');
    } catch (e) {
      await _log('syncWelcomes error: $e');
    }
    try {
      final pending = await listPendingWelcomes();
      await _log('listPendingWelcomes returned ${pending.length} items');
      return pending;
    } catch (e) {
      await _log('listPendingWelcomes error: $e');
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

    // 2. Publish the evolution event (kind 445 commit) to relays
    if (result.evolutionEventJson.isNotEmpty) {
      await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
    }

    // 3. Merge the pending commit in local MLS state
    await rust_group.mergePendingCommit(mlsGroupIdHex: mlsGroupIdHex);

    // 4. Gift-wrap and publish each welcome rumor
    // MDK welcome rumors don't have "p" tags — the recipient is the author
    // of the corresponding KeyPackage event. Welcome rumors are returned in
    // the same order as keyPackageEventsJson, so we correlate by index.
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

      // Gift-wrap the welcome for this recipient (NIP-59)
      final wrappedJson = await giftWrapWelcome(
        welcomeRumorJson: welcomeJson,
        recipientPubkeyHex: recipientHex,
      );

      // Publish the gift-wrapped welcome to relays
      await rust_relay.publishEventJson(eventJson: wrappedJson);
    }
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
    // Sync from relays first, then reload from MDK storage
    try {
      await syncWelcomes();
    } catch (_) {}
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
