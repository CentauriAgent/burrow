import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/api/account.dart';
import 'package:burrow_app/src/rust/api/identity.dart' as rust_identity;
import 'package:burrow_app/src/rust/api/keypackage.dart' as rust_kp;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// Auth state: null means not logged in.
class AuthState {
  final AccountInfo account;
  AuthState({required this.account});
}

class AuthNotifier extends AsyncNotifier<AuthState?> {
  @override
  Future<AuthState?> build() async {
    // Migrate legacy plaintext key file to keyring if it exists
    await _migrateLegacyKeyFile();

    // Try loading from the platform keyring
    if (await hasKeyringAccount()) {
      try {
        final info = await loadAccountFromKeyring();
        try {
          await rust_identity.bootstrapIdentity();
        } catch (_) {}
        _publishKeyPackage();
        return AuthState(account: info);
      } catch (_) {
        return null;
      }
    }

    return null;
  }

  /// Migrate the legacy plaintext burrow_key file to the platform keyring.
  /// Deletes the file after successful migration.
  Future<void> _migrateLegacyKeyFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final legacyFile = File('${dir.path}/burrow_key');
      if (!legacyFile.existsSync()) return;

      // Read the nsec from the file
      final nsec = legacyFile.readAsStringSync().trim();
      if (nsec.isEmpty) return;

      // Login with it (initializes state)
      await login(secretKey: nsec);
      // Save to keyring
      await saveSecretKeyToKeyring();
      // Delete the plaintext file
      legacyFile.deleteSync();
    } catch (_) {
      // Migration failed — the file stays for next attempt
    }
  }

  Future<AccountInfo> createNewIdentity() async {
    final info = await createAccount();
    await saveSecretKeyToKeyring();
    try {
      await rust_identity.bootstrapIdentity();
    } catch (_) {}
    state = AsyncData(AuthState(account: info));
    _publishKeyPackage();
    return info;
  }

  Future<AccountInfo> importIdentity(String secretKey) async {
    final info = await login(secretKey: secretKey);
    await saveSecretKeyToKeyring();
    try {
      await rust_identity.bootstrapIdentity();
    } catch (_) {}
    state = AsyncData(AuthState(account: info));
    _publishKeyPackage();
    return info;
  }

  /// Publish an MLS key package and key package relay list so other users
  /// can discover us and send invites. Non-fatal — failures are logged but
  /// do not block login/creation.
  Future<void> _publishKeyPackage() async {
    try {
      final relays = await rust_relay.listRelays();
      final urls = relays.where((r) => r.connected).map((r) => r.url).toList();
      if (urls.isEmpty) {
        urls.addAll(rust_relay.defaultRelayUrls());
      }
      await rust_kp.publishKeyPackage(relayUrls: urls);
      await rust_kp.publishKeyPackageRelays(relayUrls: urls);
    } catch (_) {}
  }

  Future<void> logoutUser() async {
    await logout();
    await deleteSecretKeyFromKeyring();
    state = const AsyncData(null);
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState?>(() {
  return AuthNotifier();
});

/// Convenience: is user logged in right now?
final isLoggedInProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  return auth.value != null;
});
