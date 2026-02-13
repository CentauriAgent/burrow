import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/groups_provider.dart';

void main() {
  group('GroupInfo model', () {
    test('creates with required fields', () {
      final group = GroupInfo(
        mlsGroupIdHex: 'abc123',
        nostrGroupIdHex: 'def456',
        name: 'Test Group',
      );
      expect(group.name, 'Test Group');
      expect(group.mlsGroupIdHex, 'abc123');
      expect(group.state, 'active');
      expect(group.epoch, 0);
      expect(group.unreadCount, 0);
      expect(group.memberCount, 0);
      expect(group.lastMessage, isNull);
      expect(group.lastMessageTime, isNull);
    });

    test('creates with all fields', () {
      final now = DateTime.now();
      final group = GroupInfo(
        mlsGroupIdHex: 'abc',
        nostrGroupIdHex: 'def',
        name: 'Full Group',
        description: 'A description',
        adminPubkeys: ['pk1', 'pk2'],
        epoch: 5,
        state: 'pending',
        lastMessage: 'Hello',
        lastMessageTime: now,
        unreadCount: 3,
        memberCount: 10,
      );
      expect(group.description, 'A description');
      expect(group.adminPubkeys.length, 2);
      expect(group.epoch, 5);
      expect(group.state, 'pending');
      expect(group.lastMessage, 'Hello');
      expect(group.lastMessageTime, now);
      expect(group.unreadCount, 3);
      expect(group.memberCount, 10);
    });
  });
}
