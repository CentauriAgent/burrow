import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'muted_group_ids';

/// Manages the set of muted group IDs.
/// Muted groups suppress notification sounds/badges.
/// Persisted to shared_preferences so it survives app restarts.
class MuteNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    state = ids.toSet();
  }

  Future<void> mute(String groupId) async {
    state = {...state, groupId};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }

  Future<void> unmute(String groupId) async {
    state = state.where((id) => id != groupId).toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }

  Future<void> toggle(String groupId) async {
    if (isMuted(groupId)) {
      await unmute(groupId);
    } else {
      await mute(groupId);
    }
  }

  bool isMuted(String groupId) => state.contains(groupId);
}

final muteProvider = NotifierProvider<MuteNotifier, Set<String>>(
  MuteNotifier.new,
);
