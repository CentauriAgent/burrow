import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'muted_group_ids';

/// Manages the set of muted group IDs.
/// Muted groups suppress notification sounds/badges.
/// Persisted to shared_preferences so it survives app restarts.
///
/// Uses AsyncNotifier so the initial SharedPreferences load is properly
/// awaited, avoiding a race where mute/unmute could overwrite the loaded data.
class MuteNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    return ids.toSet();
  }

  Future<void> mute(String groupId) async {
    final current = state.value ?? {};
    final updated = {...current, groupId};
    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated.toList());
  }

  Future<void> unmute(String groupId) async {
    final current = state.value ?? {};
    final updated = current.where((id) => id != groupId).toSet();
    state = AsyncData(updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, updated.toList());
  }

  Future<void> toggle(String groupId) async {
    if (isMuted(groupId)) {
      await unmute(groupId);
    } else {
      await mute(groupId);
    }
  }

  bool isMuted(String groupId) => state.value?.contains(groupId) ?? false;
}

final muteProvider = AsyncNotifierProvider<MuteNotifier, Set<String>>(
  MuteNotifier.new,
);
