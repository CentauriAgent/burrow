import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/messages_provider.dart';

void main() {
  group('GroupMessage model', () {
    test('creates with required fields', () {
      final msg = GroupMessage(
        eventIdHex: 'evt1',
        authorPubkeyHex: 'pub1',
        content: 'Hello',
        createdAt: 1700000000,
        mlsGroupIdHex: 'grp1',
      );
      expect(msg.content, 'Hello');
      expect(msg.kind, 1);
      expect(msg.epoch, 0);
    });

    test('createdAtDateTime converts correctly', () {
      final msg = GroupMessage(
        eventIdHex: 'evt1',
        authorPubkeyHex: 'pub1',
        content: 'Test',
        createdAt: 1700000000,
        mlsGroupIdHex: 'grp1',
      );
      final dt = msg.createdAtDateTime;
      expect(dt, DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000));
    });

    test('default kind is 1 (text note)', () {
      final msg = GroupMessage(
        eventIdHex: 'e',
        authorPubkeyHex: 'p',
        content: '',
        createdAt: 0,
        mlsGroupIdHex: 'g',
      );
      expect(msg.kind, 1);
    });

    test('custom kind preserved', () {
      final msg = GroupMessage(
        eventIdHex: 'e',
        authorPubkeyHex: 'p',
        content: '',
        createdAt: 0,
        mlsGroupIdHex: 'g',
        kind: 42,
      );
      expect(msg.kind, 42);
    });
  });
}
