import 'package:shared_preferences/shared_preferences.dart';

/// Manages user-configurable TURN server settings.
///
/// Settings are persisted via SharedPreferences and can be configured
/// in the app's settings screen. When set, they override the default
/// TURN servers returned by the Rust layer.
class TurnSettings {
  static const _keyUrl = 'turn_server_url';
  static const _keyUsername = 'turn_server_username';
  static const _keyCredential = 'turn_server_credential';

  /// Load TURN settings from persistent storage.
  /// Returns null if no custom TURN server is configured.
  static Future<TurnConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyUrl);
    if (url == null || url.isEmpty) return null;
    return TurnConfig(
      urls: url.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList(),
      username: prefs.getString(_keyUsername),
      credential: prefs.getString(_keyCredential),
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
      await prefs.remove(_keyCredential);
    } else {
      await prefs.setString(_keyUrl, url);
      if (username != null) {
        await prefs.setString(_keyUsername, username);
      } else {
        await prefs.remove(_keyUsername);
      }
      if (credential != null) {
        await prefs.setString(_keyCredential, credential);
      } else {
        await prefs.remove(_keyCredential);
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
