import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/src/rust/api/message.dart' as rust_message;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// A reaction to a message: emoji + who sent it.
class Reaction {
  final String emoji;
  final String authorPubkeyHex;
  final String eventIdHex;

  const Reaction({
    required this.emoji,
    required this.authorPubkeyHex,
    required this.eventIdHex,
  });
}

/// Manages messages for a single group. Loads history from MDK on creation
/// and accepts real-time messages from the global [messageListenerProvider].
/// Separates kind 7 reactions from kind 1 text messages.
class MessagesNotifier extends ChangeNotifier {
  final String groupId;
  List<rust_message.GroupMessage> messages = [];

  /// Reactions indexed by target event ID.
  Map<String, List<Reaction>> reactions = {};

  bool _loading = false;
  bool get loading => _loading;

  MessagesNotifier(this.groupId) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    _loading = true;
    notifyListeners();
    try {
      final all = await rust_message.getMessages(
        mlsGroupIdHex: groupId,
        limit: 100,
        offset: null,
      );
      _categorize(all);
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  void _categorize(List<rust_message.GroupMessage> all) {
    final msgs = <rust_message.GroupMessage>[];
    final rxns = <String, List<Reaction>>{};

    for (final m in all) {
      if (m.kind == BigInt.from(7)) {
        // Kind 7 = reaction — find the target event ID from e-tag
        final targetId = _extractETag(m.tags);
        if (targetId != null) {
          rxns.putIfAbsent(targetId, () => []);
          rxns[targetId]!.add(
            Reaction(
              emoji: m.content,
              authorPubkeyHex: m.authorPubkeyHex,
              eventIdHex: m.eventIdHex,
            ),
          );
        }
      } else {
        msgs.add(m);
      }
    }

    messages = msgs;
    reactions = rxns;
  }

  String? _extractETag(List<List<String>> tags) {
    for (final tag in tags) {
      if (tag.length >= 2 && tag[0] == 'e') {
        return tag[1];
      }
    }
    return null;
  }

  /// Get reactions for a specific message event ID.
  List<Reaction> reactionsFor(String eventIdHex) {
    return reactions[eventIdHex] ?? [];
  }

  /// Add a real-time message from the relay listener stream.
  void addIncomingMessage(rust_message.GroupMessage message) {
    if (message.kind == BigInt.from(7)) {
      final targetId = _extractETag(message.tags);
      if (targetId != null) {
        reactions.putIfAbsent(targetId, () => []);
        if (!reactions[targetId]!.any(
          (r) => r.eventIdHex == message.eventIdHex,
        )) {
          reactions[targetId]!.add(
            Reaction(
              emoji: message.content,
              authorPubkeyHex: message.authorPubkeyHex,
              eventIdHex: message.eventIdHex,
            ),
          );
          notifyListeners();
        }
      }
      return;
    }

    if (messages.any((m) => m.eventIdHex == message.eventIdHex)) return;
    messages = [message, ...messages];
    notifyListeners();
  }

  /// Send a message: MLS-encrypt via Rust, display immediately, publish to relays.
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    final result = await rust_message.sendMessage(
      mlsGroupIdHex: groupId,
      content: content,
    );

    // Display the message immediately using the local copy from MDK
    addIncomingMessage(result.message);

    // Publish to relays in the background (don't block UI)
    unawaited(
      rust_relay
          .publishEventJson(eventJson: result.eventJson)
          .catchError((_) => ''),
    );
  }

  /// Send a reaction to a message.
  Future<void> sendReaction(String targetEventIdHex, String emoji) async {
    final result = await rust_message.sendReaction(
      mlsGroupIdHex: groupId,
      targetEventIdHex: targetEventIdHex,
      emoji: emoji,
    );

    // Display the reaction immediately using the local copy from MDK
    addIncomingMessage(result.message);

    // Publish to relays in the background
    unawaited(
      rust_relay
          .publishEventJson(eventJson: result.eventJson)
          .catchError((_) => ''),
    );
  }

  /// Load more (older) messages for pagination.
  Future<void> loadMore() async {
    try {
      final older = await rust_message.getMessages(
        mlsGroupIdHex: groupId,
        limit: 50,
        offset: messages.length,
      );
      if (older.isNotEmpty) {
        messages = [...messages, ...older];
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Force reload from MDK storage.
  Future<void> refresh() async {
    await _loadHistory();
  }
}

/// Provider family: messages for a specific group by MLS group ID.
final messagesProvider =
    ChangeNotifierProvider.family<MessagesNotifier, String>(
      (ref, groupId) => MessagesNotifier(groupId),
    );

/// Global message listener that subscribes to kind 445 events for all groups
/// and dispatches decrypted messages to the appropriate group's provider.
/// Also handles MLS state changes (commits/proposals) by refreshing the groups list.
final messageListenerProvider = Provider<MessageListener>((ref) {
  final listener = MessageListener(ref);
  ref.onDispose(() => listener.dispose());
  return listener;
});

class MessageListener {
  final Ref _ref;
  StreamSubscription<rust_message.GroupNotification>? _subscription;

  MessageListener(this._ref);

  /// Sync missed messages from relays, then start listening for new ones.
  Future<void> start() async {
    await stop();

    try {
      await rust_message.syncGroupMessages();
    } catch (_) {}

    // Refresh group state after sync — processed commits may have
    // advanced epochs or changed group state from pending/inactive to active.
    try {
      _ref.read(groupsProvider.notifier).refresh();
    } catch (_) {}

    _subscription = rust_message.listenForGroupMessages().listen((
      notification,
    ) {
      if (notification.notificationType == 'application_message' &&
          notification.message != null) {
        _ref
            .read(messagesProvider(notification.mlsGroupIdHex).notifier)
            .addIncomingMessage(notification.message!);
      } else if (notification.notificationType == 'commit' ||
          notification.notificationType == 'proposal') {
        // MLS state changed (epoch advanced, member added/removed).
        // Refresh the groups list so the UI reflects the new state.
        _ref.read(groupsProvider.notifier).refresh();
      }
    }, onError: (_) {});
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
