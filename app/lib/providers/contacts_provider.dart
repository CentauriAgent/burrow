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
///
/// Profile resolution is batched: all members are collected first, then
/// profiles for members missing display names are fetched in parallel
/// (instead of one-by-one N+1 calls).
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  final groups = ref.watch(groupsProvider).value ?? [];
  final auth = ref.watch(authProvider);
  final selfPubkey = auth.value?.account.pubkeyHex;

  // Phase 1: Collect all unique members across groups
  final seen = <String>{};
  final memberData = <String, ({String? name, String? picture})>{};

  for (final group in groups) {
    try {
      final members = await rust_group.getGroupMembers(
        mlsGroupIdHex: group.mlsGroupIdHex,
      );
      for (final member in members) {
        if (member.pubkeyHex == selfPubkey) continue;
        if (seen.contains(member.pubkeyHex)) continue;
        seen.add(member.pubkeyHex);
        memberData[member.pubkeyHex] = (
          name: member.displayName,
          picture: member.picture,
        );
      }
    } catch (_) {}
  }

  // Phase 2: Batch-fetch profiles for members missing display names
  final needsProfile = memberData.entries
      .where((e) => e.value.name == null || e.value.name!.isEmpty)
      .map((e) => e.key)
      .toList();

  if (needsProfile.isNotEmpty) {
    final profileFutures = needsProfile.map((hex) async {
      try {
        return MapEntry(hex, await rust_identity.getCachedProfile(pubkeyHex: hex));
      } catch (_) {
        return MapEntry(hex, null);
      }
    });

    final profiles = await Future.wait(profileFutures);
    for (final entry in profiles) {
      if (entry.value != null) {
        final existing = memberData[entry.key]!;
        memberData[entry.key] = (
          name: entry.value!.displayName ?? entry.value!.name,
          picture: existing.picture ?? entry.value!.picture,
        );
      }
    }
  }

  // Phase 3: Build sorted contact list
  final contacts = memberData.entries.map((e) => Contact(
    pubkeyHex: e.key,
    displayName: e.value.name,
    picture: e.value.picture,
  )).toList();

  contacts.sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return contacts;
});
