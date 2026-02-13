import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/models/transcript.dart';

void main() {
  group('TranscriptSegment', () {
    test('fromJson creates valid segment', () {
      final json = {
        'id': 'seg_1',
        'speaker_id': 'pub123',
        'speaker_name': 'Alice',
        'text': 'Hello world',
        'start_ms': 5000,
        'end_ms': 8000,
        'confidence': 0.95,
        'language': 'en',
        'is_final': true,
      };

      final segment = TranscriptSegment.fromJson(json);
      expect(segment.id, 'seg_1');
      expect(segment.speakerName, 'Alice');
      expect(segment.text, 'Hello world');
      expect(segment.startMs, 5000);
      expect(segment.confidence, 0.95);
      expect(segment.isFinal, true);
    });

    test('toJson roundtrip preserves data', () {
      const segment = TranscriptSegment(
        id: 'seg_2',
        speakerId: 'pub456',
        speakerName: 'Bob',
        text: 'Testing roundtrip',
        startMs: 10000,
        endMs: 13000,
        confidence: 0.88,
      );

      final json = segment.toJson();
      final restored = TranscriptSegment.fromJson(json);
      expect(restored.id, segment.id);
      expect(restored.speakerName, segment.speakerName);
      expect(restored.text, segment.text);
      expect(restored.startMs, segment.startMs);
    });

    test('formattedTime shows MM:SS for short durations', () {
      const segment = TranscriptSegment(
        id: 's1',
        speakerId: '',
        speakerName: '',
        text: '',
        startMs: 65000, // 1:05
        endMs: 68000,
      );
      expect(segment.formattedTime, '01:05');
    });

    test('formattedTime shows HH:MM:SS for long durations', () {
      const segment = TranscriptSegment(
        id: 's2',
        speakerId: '',
        speakerName: '',
        text: '',
        startMs: 3661000, // 1:01:01
        endMs: 3664000,
      );
      expect(segment.formattedTime, '01:01:01');
    });

    test('fromJson handles missing fields gracefully', () {
      final segment = TranscriptSegment.fromJson({});
      expect(segment.id, '');
      expect(segment.speakerName, 'Unknown');
      expect(segment.text, '');
      expect(segment.confidence, 0.0);
      expect(segment.isFinal, true);
    });
  });

  group('TranscriptionConfig', () {
    test('default values are sensible', () {
      const config = TranscriptionConfig();
      expect(config.modelSize, 'base');
      expect(config.language, '');
      expect(config.translateToEnglish, false);
      expect(config.useGpu, true);
    });
  });
}
