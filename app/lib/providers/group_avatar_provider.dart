import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/services/group_avatar_service.dart';

/// Manages the avatar File for a single group. Notifies listeners when changed.
class GroupAvatarNotifier extends ChangeNotifier {
  final String groupId;
  File? avatarFile;

  GroupAvatarNotifier(this.groupId) {
    _load();
  }

  Future<void> _load() async {
    avatarFile = await GroupAvatarService.getAvatar(groupId);
    notifyListeners();
  }

  /// Pick a new avatar from gallery and save it.
  Future<void> pickAvatar() async {
    final file = await GroupAvatarService.pickAndSaveAvatar(groupId);
    if (file != null) {
      avatarFile = file;
      notifyListeners();
    }
  }

  /// Remove the avatar.
  Future<void> removeAvatar() async {
    await GroupAvatarService.deleteAvatar(groupId);
    avatarFile = null;
    notifyListeners();
  }
}

/// Provider family: group avatar for a specific group.
final groupAvatarProvider =
    ChangeNotifierProvider.family<GroupAvatarNotifier, String>(
      (ref, groupId) => GroupAvatarNotifier(groupId),
    );
