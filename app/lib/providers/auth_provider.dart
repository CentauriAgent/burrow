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
    final path = await _keyFilePath();
    if (!File(path).existsSync()) return null;

    try {
      final info = await loadAccountFromFile(filePath: path);
      // Bootstrap: connect relays + fetch profile. Non-fatal if it fails.
      try {
        await rust_identity.bootstrapIdentity();
      } catch (_) {}
      // Publish MLS key package so other users can invite us.
      _publishKeyPackage();
      return AuthState(account: info);
    } catch (_) {
      return null;
    }
  }

  Future<AccountInfo> createNewIdentity() async {
    final info = await createAccount();
    await saveSecretKey(filePath: await _keyFilePath());
    try {
      await rust_identity.bootstrapIdentity();
    } catch (_) {}
    state = AsyncData(AuthState(account: info));
    // Publish MLS key package so other users can invite us.
    // Fire-and-forget: don't block account creation UI.
    _publishKeyPackage();
    return info;
  }

  Future<AccountInfo> importIdentity(String secretKey) async {
    final info = await login(secretKey: secretKey);
    await saveSecretKey(filePath: await _keyFilePath());
    try {
      await rust_identity.bootstrapIdentity();
    } catch (_) {}
    state = AsyncData(AuthState(account: info));
    // Publish MLS key package so other users can invite us.
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
        // Fall back to defaults if nothing is connected yet
        urls.addAll(rust_relay.defaultRelayUrls());
      }
      await rust_kp.publishKeyPackage(relayUrls: urls);
      await rust_kp.publishKeyPackageRelays(relayUrls: urls);
    } catch (_) {
      // Non-fatal: key package publish can fail if relays are slow.
      // The user can still use the app; invites to them will fail until
      // a key package is available.
    }
  }

  Future<void> logoutUser() async {
    final path = await _keyFilePath();
    await logout();
    try {
      File(path).deleteSync();
    } catch (_) {}
    state = const AsyncData(null);
  }

  Future<String> _keyFilePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/burrow_key';
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
