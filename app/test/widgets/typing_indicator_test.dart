import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/providers/messages_provider.dart';

void main() {
  group('TypingState', () {
    test('isExpired returns false when not expired', () {
      final state = TypingState(
        pubkeyHex: 'abc123',
        expiresAt: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(state.isExpired, isFalse);
    });

    test('isExpired returns true when past expiry', () {
      final state = TypingState(
        pubkeyHex: 'abc123',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(state.isExpired, isTrue);
    });

    test('stores pubkey correctly', () {
      final state = TypingState(
        pubkeyHex: 'deadbeef01234567',
        expiresAt: DateTime.now().add(const Duration(seconds: 5)),
      );
      expect(state.pubkeyHex, 'deadbeef01234567');
    });
  });

  group('ReadStatus', () {
    test('enum values exist', () {
      expect(ReadStatus.values.length, 3);
      expect(ReadStatus.sent, isNotNull);
      expect(ReadStatus.readBySome, isNotNull);
      expect(ReadStatus.readByAll, isNotNull);
    });
  });
}
