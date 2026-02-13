import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/services/group_avatar_service.dart';
import 'package:burrow_app/src/rust/api/error.dart';

/// Manages the avatar File for a single group. Loads from local cache first,
/// then falls back to downloading from Blossom if the group has an image set.
class GroupAvatarNotifier extends ChangeNotifier {
  final String groupId;
  File? avatarFile;
  bool _loading = false;

  GroupAvatarNotifier(this.groupId) {
    _load();
  }

  Future<void> _load() async {
    // Try local cache first
    avatarFile = await GroupAvatarService.getAvatar(groupId);
    notifyListeners();

    // If no cached avatar, try downloading from Blossom
    if (avatarFile == null && !_loading) {
      _loading = true;
      try {
        final downloaded = await GroupAvatarService.downloadGroupAvatar(
          groupId: groupId,
        );
        if (downloaded != null) {
          avatarFile = downloaded;
          notifyListeners();
        }
      } catch (_) {
        // Download failed — no avatar available
      }
      _loading = false;
    }
  }

  /// Pick a new avatar, encrypt, upload to Blossom, update MLS extension.
  /// Falls back to local-only storage if Blossom upload fails.
  Future<void> pickAvatar() async {
    final picked = await GroupAvatarService.pickImage();
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final mimeType = _detectMimeType(bytes, picked.mimeType);

    try {
      final file = await GroupAvatarService.uploadGroupAvatar(
        groupId: groupId,
        imageData: bytes,
        mimeType: mimeType,
      );
      avatarFile = file;
      notifyListeners();
    } catch (e) {
      // Log the actual error to terminal
      final msg = e is BurrowError ? e.message : e.toString();
      print('DEBUG pickAvatar: Blossom upload failed: $msg');

      // Save locally as fallback
      final path = await GroupAvatarService.avatarPath(groupId);
      final file = File(path);
      await file.writeAsBytes(bytes);
      avatarFile = file;
      notifyListeners();
      rethrow; // Let UI show the error
    }
  }

  /// Remove the avatar (clear MLS extension + Blossom + local cache).
  Future<void> removeAvatar() async {
    try {
      await GroupAvatarService.removeGroupAvatar(groupId: groupId);
    } catch (_) {
      await GroupAvatarService.deleteAvatar(groupId);
    }
    avatarFile = null;
    notifyListeners();
  }

  /// Detect MIME type from file magic bytes, falling back to the provided hint.
  static String _detectMimeType(Uint8List bytes, String? hint) {
    if (bytes.length >= 8) {
      // PNG: 89 50 4E 47
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      // JPEG: FF D8 FF
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }
      // WebP: RIFF....WEBP
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes.length >= 12 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
      // GIF: GIF8
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38) {
        return 'image/gif';
      }
    }
    return hint ?? 'image/jpeg';
  }

  /// Force re-download from Blossom.
  Future<void> refresh() async {
    await GroupAvatarService.deleteAvatar(groupId);
    avatarFile = null;
    notifyListeners();
    await _load();
  }
}

/// Provider family: group avatar for a specific group.
final groupAvatarProvider =
    ChangeNotifierProvider.family<GroupAvatarNotifier, String>(
      (ref, groupId) => GroupAvatarNotifier(groupId),
    );
