import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/identity.dart' as rust_identity;

/// A contact derived from group membership.
class Contact {
  final String pubkeyHex;
  final String? displayName;
  final String? picture;

  const Contact({
    required this.pubkeyHex,
    this.displayName,
    this.picture,
  });

  /// Best name for display, falling back to truncated pubkey.
  String get name {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (pubkeyHex.length > 16) {
      return '${pubkeyHex.substring(0, 8)}...${pubkeyHex.substring(pubkeyHex.length - 8)}';
    }
    return pubkeyHex;
  }

  /// Sort key: lowercase name for alphabetical sorting.
  String get sortKey => name.toLowerCase();
}

/// Collects all unique peers across all groups the user belongs to.
/// Returns them sorted alphabetically by display name.
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final groups = ref.watch(groupsProvider).value ?? [];
  final auth = ref.watch(authProvider);
  final selfPubkey = auth.value?.account.pubkeyHex;

  final seen = <String>{};
  final contacts = <Contact>[];

  for (final group in groups) {
    try {
      final members = await rust_group.getGroupMembers(
        mlsGroupIdHex: group.mlsGroupIdHex,
      );
      for (final member in members) {
        if (member.pubkeyHex == selfPubkey) continue;
        if (seen.contains(member.pubkeyHex)) continue;
        seen.add(member.pubkeyHex);

        // Use cached profile data from MemberInfo first
        String? name = member.displayName;
        String? picture = member.picture;

        // If no cached data, try fetching profile
        if (name == null || name.isEmpty) {
          try {
            final profile = await rust_identity.getCachedProfile(
              pubkeyHex: member.pubkeyHex,
            );
            name = profile.displayName ?? profile.name;
            picture = picture ?? profile.picture;
          } catch (_) {}
        }

        contacts.add(Contact(
          pubkeyHex: member.pubkeyHex,
          displayName: name,
          picture: picture,
        ));
      }
    } catch (_) {}
  }

  contacts.sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return contacts;
});
