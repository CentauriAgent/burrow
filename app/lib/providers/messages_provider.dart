import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:burrow_app/src/rust/api/message.dart' as rust_message;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// Manages messages for a single group. Loads history from MDK on creation
/// and accepts real-time messages from the global [messageListenerProvider].
class MessagesNotifier extends ChangeNotifier {
  final String groupId;
  List<rust_message.GroupMessage> messages = [];
  bool _loading = false;
  bool get loading => _loading;

  MessagesNotifier(this.groupId) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    _loading = true;
    notifyListeners();
    try {
      messages = await rust_message.getMessages(
        mlsGroupIdHex: groupId,
        limit: 50,
        offset: null,
      );
    } catch (_) {
      // MDK may not have messages yet
    }
    _loading = false;
    notifyListeners();
  }

  /// Add a real-time message from the relay listener stream.
  void addIncomingMessage(rust_message.GroupMessage message) {
    if (messages.any((m) => m.eventIdHex == message.eventIdHex)) return;
    messages = [message, ...messages];
    notifyListeners();
  }

  /// Send a message: MLS-encrypt via Rust, publish to relays.
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    // 1. MLS-encrypt and get kind 445 event JSON
    final eventJson = await rust_message.sendMessage(
      mlsGroupIdHex: groupId,
      content: content,
    );

    // 2. Publish to connected relays
    await rust_relay.publishEventJson(eventJson: eventJson);

    // 3. Reload from MDK to get the stored message with correct metadata
    await _loadHistory();
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
final messageListenerProvider = Provider<MessageListener>((ref) {
  final listener = MessageListener(ref);
  ref.onDispose(() => listener.dispose());
  return listener;
});

class MessageListener {
  final Ref _ref;
  StreamSubscription<rust_message.GroupMessage>? _subscription;

  MessageListener(this._ref);

  /// Sync missed messages from relays, then start listening for new ones.
  Future<void> start() async {
    await stop();

    // Catch-up: fetch messages sent while the app was offline
    try {
      await rust_message.syncGroupMessages();
    } catch (_) {
      // Sync failure is non-fatal — continue to live listener
    }

    _subscription = rust_message.listenForGroupMessages().listen(
      (message) {
        _ref
            .read(messagesProvider(message.mlsGroupIdHex).notifier)
            .addIncomingMessage(message);
      },
      onError: (_) {
        // Stream error — relay disconnected or similar
      },
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
