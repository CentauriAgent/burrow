import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/invite.dart';

class InviteNotifier extends AsyncNotifier<List<WelcomeInfo>> {
  @override
  Future<List<WelcomeInfo>> build() async {
    try {
      return await listPendingWelcomes();
    } catch (_) {
      return [];
    }
  }

  /// Send invites: fetch key packages and add members to group.
  Future<void> sendInvite({
    required String mlsGroupIdHex,
    required List<String> keyPackageEventsJson,
  }) async {
    await addMembers(
      mlsGroupIdHex: mlsGroupIdHex,
      keyPackageEventsJson: keyPackageEventsJson,
    );
    // TODO: publish evolution event to relays, merge pending commit,
    // then gift-wrap welcome rumors per MIP-02
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

final inviteProvider =
    AsyncNotifierProvider<InviteNotifier, List<WelcomeInfo>>(() {
  return InviteNotifier();
});

/// Count of pending invites for badge display.
final pendingInviteCountProvider = Provider<int>((ref) {
  final invites = ref.watch(inviteProvider);
  return invites.value?.where((w) => w.state == 'pending').length ?? 0;
});
