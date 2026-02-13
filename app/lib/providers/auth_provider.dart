import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/account.dart';

/// Auth state: null means not logged in.
class AuthState {
  final AccountInfo account;
  AuthState({required this.account});
}

class AuthNotifier extends AsyncNotifier<AuthState?> {
  @override
  Future<AuthState?> build() async {
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return null;
    try {
      final info = await getCurrentAccount();
      return AuthState(account: info);
    } catch (_) {
      return null;
    }
  }

  Future<AccountInfo> createNewIdentity() async {
    final info = await createAccount();
    state = AsyncData(AuthState(account: info));
    return info;
  }

  Future<AccountInfo> importIdentity(String secretKey) async {
    final info = await login(secretKey: secretKey);
    state = AsyncData(AuthState(account: info));
    return info;
  }

  Future<void> logoutUser() async {
    await logout();
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
