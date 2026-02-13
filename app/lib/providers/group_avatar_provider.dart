import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/services/group_avatar_service.dart';
import 'package:burrow_app/src/rust/api/error.dart';

/// Holds the avatar state for a group: the local File (if any) and a
/// version counter to force UI rebuilds when the file changes.
class GroupAvatarState {
  final File? avatarFile;
  final int version;

  const GroupAvatarState({this.avatarFile, this.version = 0});

  GroupAvatarState copyWith({File? avatarFile, int? version}) =>
      GroupAvatarState(
        avatarFile: avatarFile ?? this.avatarFile,
        version: version ?? this.version,
      );

  GroupAvatarState cleared({int? version}) =>
      GroupAvatarState(avatarFile: null, version: version ?? this.version);
}

/// Provider family: avatar state for a specific group.
/// Uses StateNotifierProvider for reliable rebuild notifications.
final groupAvatarProvider =
    StateNotifierProvider.family<GroupAvatarNotifier, GroupAvatarState, String>(
      (ref, groupId) => GroupAvatarNotifier(groupId),
    );

class GroupAvatarNotifier extends StateNotifier<GroupAvatarState> {
  final String groupId;
  bool _loading = false;

  GroupAvatarNotifier(this.groupId) : super(const GroupAvatarState()) {
    _load();
  }

  Future<void> _load() async {
    // Try local cache first
    final cached = await GroupAvatarService.getAvatar(groupId);
    if (cached != null) {
      state = GroupAvatarState(avatarFile: cached, version: state.version + 1);
      return;
    }

    // If no cache, try downloading from Blossom
    if (!_loading) {
      _loading = true;
      try {
        final downloaded = await GroupAvatarService.downloadGroupAvatar(
          groupId: groupId,
        );
        if (downloaded != null) {
          state = GroupAvatarState(
            avatarFile: downloaded,
            version: state.version + 1,
          );
        }
      } catch (_) {}
      _loading = false;
    }
  }

  /// Pick a new avatar, encrypt, upload to Blossom, update MLS extension.
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
      state = GroupAvatarState(avatarFile: file, version: state.version + 1);
    } catch (e) {
      final msg = e is BurrowError ? e.message : e.toString();
      print('DEBUG pickAvatar: Blossom upload failed: $msg');

      // Save locally as fallback
      final path = await GroupAvatarService.avatarPath(groupId);
      final file = File(path);
      await file.writeAsBytes(bytes);
      state = GroupAvatarState(avatarFile: file, version: state.version + 1);
      rethrow;
    }
  }

  /// Remove the avatar.
  Future<void> removeAvatar() async {
    try {
      await GroupAvatarService.removeGroupAvatar(groupId: groupId);
    } catch (_) {
      await GroupAvatarService.deleteAvatar(groupId);
    }
    state = GroupAvatarState(avatarFile: null, version: state.version + 1);
  }

  /// Force re-download from Blossom.
  Future<void> refresh() async {
    await GroupAvatarService.deleteAvatar(groupId);
    state = GroupAvatarState(avatarFile: null, version: state.version + 1);
    await _load();
  }

  static String _detectMimeType(Uint8List bytes, String? hint) {
    if (bytes.length >= 8) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47)
        return 'image/png';
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF)
        return 'image/jpeg';
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
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38)
        return 'image/gif';
    }
    return hint ?? 'image/jpeg';
  }
}
