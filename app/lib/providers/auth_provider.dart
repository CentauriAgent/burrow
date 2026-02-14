import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/api/account.dart';
import 'package:burrow_app/src/rust/api/identity.dart' as rust_identity;

/// Auth state: null means not logged in.
class AuthState {
  final AccountInfo account;
  AuthState({required this.account});
}

class AuthNotifier extends AsyncNotifier<AuthState?> {
  @override
  Future<AuthState?> build() async {
    // Try to restore from persisted key file
    final path = await _keyFilePath();
    if (File(path).existsSync()) {
      try {
        final info = await loadAccountFromFile(filePath: path);
        // Bootstrap: connect default + NIP-65 relays, fetch own profile
        rust_identity.bootstrapIdentity().ignore();
        return AuthState(account: info);
      } catch (_) {
        // Corrupt key file — delete it
        try {
          File(path).deleteSync();
        } catch (_) {}
        return null;
      }
    }
    return null;
  }

  Future<AccountInfo> createNewIdentity() async {
    final info = await createAccount();
    await saveSecretKey(filePath: await _keyFilePath());
    state = AsyncData(AuthState(account: info));
    // Bootstrap: connect relays, fetch profile, discover NIP-65 relays
    rust_identity.bootstrapIdentity().ignore();
    return info;
  }

  Future<AccountInfo> importIdentity(String secretKey) async {
    final info = await login(secretKey: secretKey);
    await saveSecretKey(filePath: await _keyFilePath());
    state = AsyncData(AuthState(account: info));
    // Bootstrap: connect relays, fetch profile, discover NIP-65 relays
    rust_identity.bootstrapIdentity().ignore();
    return info;
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
