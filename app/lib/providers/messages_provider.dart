import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Message model (mirrors Rust GroupMessage FFI struct).
class GroupMessage {
  final String eventIdHex;
  final String authorPubkeyHex;
  final String content;
  final int createdAt;
  final String mlsGroupIdHex;
  final int kind;
  final String wrapperEventIdHex;
  final int epoch;

  GroupMessage({
    required this.eventIdHex,
    required this.authorPubkeyHex,
    required this.content,
    required this.createdAt,
    required this.mlsGroupIdHex,
    this.kind = 1,
    this.wrapperEventIdHex = '',
    this.epoch = 0,
  });

  DateTime get createdAtDateTime =>
      DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
}

/// Simple messages manager accessed via a provider family.
class MessagesManager {
  final List<GroupMessage> messages = [];
  final String groupId;

  MessagesManager(this.groupId);

  void sendMessage(String content) {
    if (content.trim().isEmpty) return;
    messages.insert(
      0,
      GroupMessage(
        eventIdHex: DateTime.now().millisecondsSinceEpoch.toRadixString(16),
        authorPubkeyHex: 'self',
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        mlsGroupIdHex: groupId,
      ),
    );
  }

  void addMessage(GroupMessage message) {
    if (messages.any((m) => m.eventIdHex == message.eventIdHex)) return;
    messages.insert(0, message);
  }
}

/// Provider family: messages for a specific group by MLS group ID.
final messagesProvider = Provider.family<MessagesManager, String>((ref, groupId) {
  return MessagesManager(groupId);
});

/// Currently active group ID (for the chat view).
final activeGroupIdProvider = Provider<String?>((ref) => null);
