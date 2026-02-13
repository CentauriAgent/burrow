import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/services/group_avatar_service.dart';

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
  Future<void> pickAvatar() async {
    final picked = await GroupAvatarService.pickImage();
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final mimeType = picked.mimeType ?? 'image/jpeg';

    final file = await GroupAvatarService.uploadGroupAvatar(
      groupId: groupId,
      imageData: bytes,
      mimeType: mimeType,
    );
    avatarFile = file;
    notifyListeners();
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
