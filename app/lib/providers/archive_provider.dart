import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'archived_group_ids';

/// Manages the set of archived (hidden) group IDs.
/// Persisted to shared_preferences so it survives app restarts.
class ArchiveNotifier extends Notifier<Set<String>> {
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

  Future<void> archive(String groupId) async {
    state = {...state, groupId};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }

  Future<void> unarchive(String groupId) async {
    state = state.where((id) => id != groupId).toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }

  bool isArchived(String groupId) => state.contains(groupId);
}

final archiveProvider = NotifierProvider<ArchiveNotifier, Set<String>>(
  ArchiveNotifier.new,
);
