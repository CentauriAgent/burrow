import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages user-configurable TURN server settings.
///
/// URL and username are stored in SharedPreferences (not secret).
/// The credential (password) is stored in flutter_secure_storage
/// (Keychain on iOS, EncryptedSharedPreferences on Android).
class TurnSettings {
  static const _keyUrl = 'turn_server_url';
  static const _keyUsername = 'turn_server_username';
  static const _keyCredential = 'turn_server_credential';

  static const _secureStorage = FlutterSecureStorage();

  /// Load TURN settings from persistent storage.
  /// Returns null if no custom TURN server is configured.
  static Future<TurnConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyUrl);
    if (url == null || url.isEmpty) return null;
    final credential = await _secureStorage.read(key: _keyCredential);
    return TurnConfig(
      urls: url.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList(),
      username: prefs.getString(_keyUsername),
      credential: credential,
    );
  }

  /// Save custom TURN server settings.
  /// Pass null or empty url to clear (revert to defaults).
  static Future<void> save({
    required String? url,
    String? username,
    String? credential,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (url == null || url.isEmpty) {
      await prefs.remove(_keyUrl);
      await prefs.remove(_keyUsername);
      await _secureStorage.delete(key: _keyCredential);
    } else {
      await prefs.setString(_keyUrl, url);
      if (username != null) {
        await prefs.setString(_keyUsername, username);
      } else {
        await prefs.remove(_keyUsername);
      }
      if (credential != null) {
        await _secureStorage.write(key: _keyCredential, value: credential);
      } else {
        await _secureStorage.delete(key: _keyCredential);
      }
    }
  }
}

/// TURN server configuration.
class TurnConfig {
  final List<String> urls;
  final String? username;
  final String? credential;

  const TurnConfig({
    required this.urls,
    this.username,
    this.credential,
  });
}
