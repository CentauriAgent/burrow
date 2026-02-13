/// Data models for real-time transcription.
library;

/// A single transcript segment with speaker and timing info.
class TranscriptSegment {
  final String id;
  final String speakerId;
  final String speakerName;
  final String text;
  final int startMs;
  final int endMs;
  final double confidence;
  final String language;
  final bool isFinal;

  const TranscriptSegment({
    required this.id,
    required this.speakerId,
    required this.speakerName,
    required this.text,
    required this.startMs,
    required this.endMs,
    this.confidence = 0.0,
    this.language = 'en',
    this.isFinal = true,
  });

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptSegment(
      id: json['id'] as String? ?? '',
      speakerId: json['speaker_id'] as String? ?? '',
      speakerName: json['speaker_name'] as String? ?? 'Unknown',
      text: json['text'] as String? ?? '',
      startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
      endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      language: json['language'] as String? ?? 'en',
      isFinal: json['is_final'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'speaker_id': speakerId,
        'speaker_name': speakerName,
        'text': text,
        'start_ms': startMs,
        'end_ms': endMs,
        'confidence': confidence,
        'language': language,
        'is_final': isFinal,
      };

  /// Format start time as MM:SS or HH:MM:SS.
  String get formattedTime {
    final totalSeconds = startMs ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

/// Configuration for the transcription engine.
class TranscriptionConfig {
  final String modelSize;
  final String language;
  final bool translateToEnglish;
  final bool useGpu;

  const TranscriptionConfig({
    this.modelSize = 'base',
    this.language = '',
    this.translateToEnglish = false,
    this.useGpu = true,
  });
}
