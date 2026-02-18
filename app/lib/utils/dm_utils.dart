import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/providers/group_provider.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/invite_provider.dart';
import 'package:burrow_app/providers/relay_provider.dart';

/// Find an existing DM with [peerPubkeyHex], or create one and invite the peer.
/// Returns the MLS group ID hex of the DM.
Future<String> findOrCreateDm(WidgetRef ref, String peerPubkeyHex) async {
  // Check existing groups for a DM with this peer
  final groups = ref.read(groupsProvider).value ?? [];
  for (final g in groups) {
    if (g.isDirectMessage && g.dmPeerPubkeyHex == peerPubkeyHex) {
      return g.mlsGroupIdHex;
    }
  }

  // Create new DM group
  final auth = ref.read(authProvider).value!;
  final relayUrls = ref.read(relayProvider.notifier).defaultRelays;
  final short = peerPubkeyHex.length > 16
      ? '${peerPubkeyHex.substring(0, 8)}...${peerPubkeyHex.substring(peerPubkeyHex.length - 8)}'
      : peerPubkeyHex;
  final result = await ref
      .read(groupProvider.notifier)
      .createNewGroup(
        name: 'DM-$short',
        description: '__dm__',
        adminPubkeysHex: [auth.account.pubkeyHex],
        relayUrls: relayUrls,
      );

  // Fetch peer's key package and invite them to the group
  final inviteNotifier = ref.read(inviteProvider.notifier);
  final keyPackageJson = await inviteNotifier.fetchUserKeyPackage(
    peerPubkeyHex,
  );
  await inviteNotifier.sendInvite(
    mlsGroupIdHex: result.mlsGroupIdHex,
    keyPackageEventsJson: [keyPackageJson],
  );

  await ref.read(groupsProvider.notifier).refresh();
  return result.mlsGroupIdHex;
}
