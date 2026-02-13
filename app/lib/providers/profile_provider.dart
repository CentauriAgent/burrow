import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/providers/auth_provider.dart';
import 'package:burrow_app/src/rust/api/identity.dart' as rust_identity;

/// Provides the logged-in user's Nostr profile (display name, picture URL).
/// Fetches from cache first, then relays.
final selfProfileProvider = FutureProvider<rust_identity.ProfileData?>((
  ref,
) async {
  final auth = ref.watch(authProvider);
  final pubkey = auth.value?.account.pubkeyHex;
  if (pubkey == null) return null;

  try {
    // Try cache first (non-blocking)
    final cached = await rust_identity.fetchProfile(
      pubkeyHex: pubkey,
      blockingSync: false,
    );
    if (cached.displayName != null || cached.picture != null) return cached;

    // If cache empty, try relay
    return await rust_identity.fetchProfile(
      pubkeyHex: pubkey,
      blockingSync: true,
    );
  } catch (_) {
    return null;
  }
});
