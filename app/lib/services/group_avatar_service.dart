import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// Manages group avatar images via encrypted Blossom (MIP-01) with local caching.
///
/// Upload flow: pick image -> encrypt via MDK -> upload to Blossom with NIP-98 auth
///   -> update MLS group extension -> publish evolution event to relays.
///
/// Download flow: check local cache -> if miss, download encrypted blob from Blossom
///   -> decrypt via MDK -> cache locally.
class GroupAvatarService {
  static final _picker = ImagePicker();
  static String? _basePath;

  static Future<String> _getCachePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = '${dir.path}/group_avatars';
    await Directory(_basePath!).create(recursive: true);
    return _basePath!;
  }

  /// Get the avatar cache file path for a group.
  static Future<String> avatarPath(String groupId) async {
    final base = await _getCachePath();
    return '$base/$groupId.png';
  }

  /// Get cached avatar file for a group, or null if not cached.
  static Future<File?> getAvatar(String groupId) async {
    final path = await avatarPath(groupId);
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Pick an image from gallery. Returns the picked file, or null if cancelled.
  static Future<XFile?> pickImage() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
  }

  /// Upload an image as the group's avatar via encrypted Blossom + MLS update.
  /// Returns the cached File of the avatar on success.
  static Future<File> uploadGroupAvatar({
    required String groupId,
    required Uint8List imageData,
    required String mimeType,
    String? blossomServerUrl,
  }) async {
    final serverUrl =
        blossomServerUrl ?? await rust_group.defaultBlossomServer();

    // Encrypt, upload to Blossom, update MLS extension
    final result = await rust_group.uploadGroupImage(
      mlsGroupIdHex: groupId,
      imageData: imageData,
      mimeType: mimeType,
      blossomServerUrl: serverUrl,
    );

    // Publish the evolution event to relays
    if (result.evolutionEventJson.isNotEmpty) {
      await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
    }

    // Merge the pending commit
    await rust_group.mergePendingCommit(mlsGroupIdHex: groupId);

    // Cache the original (unencrypted) image locally
    final path = await avatarPath(groupId);
    final file = File(path);
    await file.writeAsBytes(imageData);
    return file;
  }

  /// Download and decrypt the group's avatar from Blossom.
  /// Returns the cached File, or null if the group has no avatar.
  static Future<File?> downloadGroupAvatar({
    required String groupId,
    String? blossomServerUrl,
  }) async {
    final serverUrl =
        blossomServerUrl ?? await rust_group.defaultBlossomServer();

    try {
      final decrypted = await rust_group.downloadGroupImage(
        mlsGroupIdHex: groupId,
        blossomServerUrl: serverUrl,
      );
      final path = await avatarPath(groupId);
      final file = File(path);
      await file.writeAsBytes(decrypted);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Remove the group's avatar. Clears MLS extension and local cache.
  static Future<void> removeGroupAvatar({required String groupId}) async {
    final result = await rust_group.removeGroupImage(mlsGroupIdHex: groupId);

    // Publish the evolution event
    if (result.evolutionEventJson.isNotEmpty) {
      await rust_relay.publishEventJson(eventJson: result.evolutionEventJson);
    }

    // Merge pending commit
    await rust_group.mergePendingCommit(mlsGroupIdHex: groupId);

    // Clear local cache
    await deleteAvatar(groupId);
  }

  /// Delete the local cached avatar.
  static Future<void> deleteAvatar(String groupId) async {
    final path = await avatarPath(groupId);
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}
