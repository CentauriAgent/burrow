import 'package:burrow_app/src/rust/api/identity.dart' as rust_identity;

/// Stateless service for fetching user profile data.
///
/// Follows the White Noise two-step fetch pattern:
/// 1. Try non-blocking (cache) first — returns immediately.
/// 2. If empty, try blocking (relay) — waits up to 10s.
class UserService {
  final String pubkeyHex;

  UserService({required this.pubkeyHex});

  /// Fetch profile using the two-step cache-then-relay pattern.
  Future<rust_identity.ProfileData> fetchProfile() async {
    final cached = await rust_identity.fetchProfile(
      pubkeyHex: pubkeyHex,
      blockingSync: false,
    );

    if (_isProfileEmpty(cached)) {
      return rust_identity.fetchProfile(
        pubkeyHex: pubkeyHex,
        blockingSync: true,
      );
    }

    return cached;
  }

  static bool _isProfileEmpty(rust_identity.ProfileData profile) {
    return profile.name == null &&
        profile.displayName == null &&
        profile.picture == null;
  }

  /// Best display name from profile: prefers displayName, falls back to name.
  static String? presentName(rust_identity.ProfileData? profile) {
    if (profile == null) return null;
    if (profile.displayName != null && profile.displayName!.isNotEmpty) {
      return profile.displayName;
    }
    if (profile.name != null && profile.name!.isNotEmpty) {
      return profile.name;
    }
    return null;
  }

  /// Truncated hex pubkey for display when no name is available.
  static String truncatePubkey(String hex) {
    if (hex.length > 16) {
      return '${hex.substring(0, 8)}...${hex.substring(hex.length - 8)}';
    }
    return hex;
  }

  /// Display name with fallback to truncated pubkey.
  static String displayName(
    rust_identity.ProfileData? profile,
    String pubkeyHex,
  ) {
    return presentName(profile) ?? truncatePubkey(pubkeyHex);
  }
}
