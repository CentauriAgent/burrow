import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Manages local group avatar images stored on-device.
///
/// Avatars are saved as PNG files in the app's support directory under
/// `group_avatars/<groupId>.png`. This is a local-only solution until
/// encrypted Blossom upload is implemented.
class GroupAvatarService {
  static final _picker = ImagePicker();
  static String? _basePath;

  static Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = '${dir.path}/group_avatars';
    await Directory(_basePath!).create(recursive: true);
    return _basePath!;
  }

  /// Get the avatar file path for a group (may not exist).
  static Future<String> avatarPath(String groupId) async {
    final base = await _getBasePath();
    return '$base/$groupId.png';
  }

  /// Get the avatar File if it exists, or null.
  static Future<File?> getAvatar(String groupId) async {
    final path = await avatarPath(groupId);
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  /// Pick an image from gallery and save as the group's avatar.
  /// Returns the saved File, or null if cancelled.
  static Future<File?> pickAndSaveAvatar(String groupId) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return null;

    final path = await avatarPath(groupId);
    final saved = await File(picked.path).copy(path);
    return saved;
  }

  /// Delete a group's avatar.
  static Future<void> deleteAvatar(String groupId) async {
    final path = await avatarPath(groupId);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
