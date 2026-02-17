import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    try {
      final hasAccount = await hasKeyringAccount();
      if (hasAccount) {
        final info = await loadAccountFromKeyring();
        try {
          await rust_identity.bootstrapIdentity();
        } catch (_) {}
        _publishKeyPackage();
        return AuthState(account: info);
      }
    } catch (_) {}

    return null;
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
