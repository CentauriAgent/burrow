import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/groups_provider.dart';
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;

rust_group.GroupInfo makeRustGroup({
  String mlsGroupIdHex = 'abc123',
  String nostrGroupIdHex = 'def456',
  String name = 'Test Group',
  String description = '',
  List<String> adminPubkeys = const [],
  BigInt? epoch,
  String state = 'active',
  int memberCount = 0,
  bool isDirectMessage = false,
  String? dmPeerDisplayName,
  String? dmPeerPicture,
  String? dmPeerPubkeyHex,
}) {
  return rust_group.GroupInfo(
    mlsGroupIdHex: mlsGroupIdHex,
    nostrGroupIdHex: nostrGroupIdHex,
    name: name,
    description: description,
    adminPubkeys: adminPubkeys,
    epoch: epoch ?? BigInt.zero,
    state: state,
    memberCount: memberCount,
    isDirectMessage: isDirectMessage,
    dmPeerDisplayName: dmPeerDisplayName,
    dmPeerPicture: dmPeerPicture,
    dmPeerPubkeyHex: dmPeerPubkeyHex,
    imageHashHex: null,
    hasImage: false,
  );
}

void main() {
  group('GroupInfo model', () {
    test('creates with required fields', () {
      final group = GroupInfo(rustGroup: makeRustGroup());
      expect(group.name, 'Test Group');
      expect(group.mlsGroupIdHex, 'abc123');
      expect(group.state, 'active');
      expect(group.epoch, BigInt.zero);
      expect(group.unreadCount, 0);
      expect(group.memberCount, 0);
      expect(group.lastMessage, isNull);
      expect(group.lastMessageTime, isNull);
    });

    test('creates with all fields', () {
      final now = DateTime.now();
      final group = GroupInfo(
        rustGroup: makeRustGroup(
          name: 'Full Group',
          description: 'A description',
          adminPubkeys: ['pk1', 'pk2'],
          epoch: BigInt.from(5),
          state: 'pending',
          memberCount: 10,
        ),
        lastMessage: 'Hello',
        lastMessageTime: now,
        unreadCount: 3,
      );
      expect(group.description, 'A description');
      expect(group.adminPubkeys.length, 2);
      expect(group.epoch, BigInt.from(5));
      expect(group.state, 'pending');
      expect(group.lastMessage, 'Hello');
      expect(group.lastMessageTime, now);
      expect(group.unreadCount, 3);
      expect(group.memberCount, 10);
    });

    test('displayName uses DM peer name for direct messages', () {
      final group = GroupInfo(
        rustGroup: makeRustGroup(
          name: 'DM-abcd1234',
          isDirectMessage: true,
          dmPeerDisplayName: 'Alice',
          dmPeerPubkeyHex: 'abcdef1234567890abcdef1234567890',
        ),
      );
      expect(group.displayName, 'Alice');
    });

    test('displayName falls back to group name', () {
      final group = GroupInfo(rustGroup: makeRustGroup(name: 'My Group'));
      expect(group.displayName, 'My Group');
    });
  });
}
