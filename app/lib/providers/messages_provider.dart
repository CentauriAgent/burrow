import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Message model (mirrors Rust GroupMessage FFI struct).
/// TODO: Replace with generated FFI binding when flutter_rust_bridge codegen runs.
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

/// Provider family: messages for a specific group by MLS group ID.
class MessagesNotifier extends FamilyAsyncNotifier<List<GroupMessage>, String> {
  @override
  Future<List<GroupMessage>> build(String arg) async {
    // TODO: Call Rust FFI get_messages(mlsGroupIdHex: arg) when bindings are generated
    return [];
  }

  /// Load more messages (pagination).
  Future<void> loadMore() async {
    final current = state.valueOrNull ?? [];
    // TODO: Call get_messages with offset = current.length
    // final older = await getMessages(mlsGroupIdHex: arg, limit: 50, offset: current.length);
    // state = AsyncData([...current, ...older]);
    state = AsyncData(current);
  }

  /// Send a message to this group.
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    // TODO: Call Rust FFI send_message(mlsGroupIdHex: arg, content: content)
    // Then publish returned kind 445 event to relays via relay_provider
    // For now, add optimistic local message
    final current = state.valueOrNull ?? [];
    final msg = GroupMessage(
      eventIdHex: DateTime.now().millisecondsSinceEpoch.toRadixString(16),
      authorPubkeyHex: 'self', // TODO: get from auth_provider
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      mlsGroupIdHex: arg,
    );
    state = AsyncData([msg, ...current]);
  }

  /// Process an incoming message and add it to the list.
  void addMessage(GroupMessage message) {
    final current = state.valueOrNull ?? [];
    // Deduplicate by event ID
    if (current.any((m) => m.eventIdHex == message.eventIdHex)) return;
    state = AsyncData([message, ...current]);
  }
}

final messagesProvider = AsyncNotifierProvider.family<MessagesNotifier,
    List<GroupMessage>, String>(() {
  return MessagesNotifier();
});

/// Currently active group ID (for the chat view).
final activeGroupIdProvider = StateProvider<String?>((ref) => null);
