/// Service bridging WebRTC audio streams to the Rust transcription engine.
///
/// Captures audio from remote WebRTC tracks, resamples to 16kHz mono PCM,
/// and feeds chunks to the Rust transcription API via FFI.
library;

import 'dart:async';
import 'dart:convert';
import 'package:burrow_app/models/transcript.dart';

/// Manages the audio capture and transcription pipeline.
class TranscriptionService {
  final _segmentController = StreamController<TranscriptSegment>.broadcast();
  final _statusController = StreamController<TranscriptionStatus>.broadcast();

  /// Stream of new transcript segments as they arrive.
  Stream<TranscriptSegment> get onSegment => _segmentController.stream;

  /// Stream of transcription status changes.
  Stream<TranscriptionStatus> get onStatus => _statusController.stream;

  /// All segments accumulated in this session.
  final List<TranscriptSegment> _segments = [];
  List<TranscriptSegment> get segments => List.unmodifiable(_segments);

  TranscriptionStatus _status = TranscriptionStatus.idle;
  TranscriptionStatus get status => _status;

  Timer? _processingTimer;

  /// Initialize the transcription engine with model config.
  Future<void> initialize({
    TranscriptionConfig config = const TranscriptionConfig(),
  }) async {
    _updateStatus(TranscriptionStatus.loading);

    // In production: calls Rust init_transcription() via FFI.
    // rust_transcription.initTranscription(
    //   modelSize: config.modelSize,
    //   language: config.language,
    //   translateToEnglish: config.translateToEnglish,
    //   useGpu: config.useGpu,
    // );

    _updateStatus(TranscriptionStatus.ready);
  }

  /// Start transcription for a call.
  Future<void> startTranscription({required String callId}) async {
    if (_status != TranscriptionStatus.ready &&
        _status != TranscriptionStatus.paused) {
      return;
    }

    _segments.clear();
    _updateStatus(TranscriptionStatus.transcribing);

    // In production: calls Rust start_transcription(callId) via FFI.
    // rust_transcription.startTranscription(callId: callId);

    // Start periodic processing (simulates real-time chunk processing).
    _processingTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _processAudioChunk(),
    );
  }

  /// Register a speaker's WebRTC track ID to their Nostr identity.
  void registerSpeaker({
    required String trackId,
    required String pubkeyHex,
    required String displayName,
  }) {
    // In production: calls Rust register_speaker() via FFI.
    // rust_transcription.registerSpeaker(
    //   trackId: trackId,
    //   pubkeyHex: pubkeyHex,
    //   displayName: displayName,
    // );
  }

  /// Pause transcription.
  void pause() {
    if (_status == TranscriptionStatus.transcribing) {
      _processingTimer?.cancel();
      _updateStatus(TranscriptionStatus.paused);
    }
  }

  /// Resume transcription.
  void resume() {
    if (_status == TranscriptionStatus.paused) {
      _updateStatus(TranscriptionStatus.transcribing);
      _processingTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _processAudioChunk(),
      );
    }
  }

  /// Stop transcription and return all segments.
  Future<List<TranscriptSegment>> stopTranscription() async {
    _processingTimer?.cancel();
    _updateStatus(TranscriptionStatus.ready);

    // In production: calls Rust stop_transcription() via FFI.
    // final rustSegments = rust_transcription.stopTranscription();

    return List.from(_segments);
  }

  /// Search current session's segments.
  List<TranscriptSegment> search(String query) {
    final queryLower = query.toLowerCase();
    return _segments
        .where((s) => s.text.toLowerCase().contains(queryLower))
        .toList();
  }

  /// Get full transcript as formatted text.
  String getFormattedTranscript() {
    final buffer = StringBuffer();
    for (final seg in _segments) {
      buffer.writeln('[${seg.formattedTime}] ${seg.speakerName}: ${seg.text}');
    }
    return buffer.toString();
  }

  /// Get transcript as JSON (for Rust meeting intelligence processing).
  String getSegmentsJson() {
    return jsonEncode(_segments.map((s) => s.toJson()).toList());
  }

  void _processAudioChunk() {
    // In production, this would:
    // 1. Read audio from WebRTC track's AudioRenderer
    // 2. Resample to 16kHz mono PCM f32
    // 3. Feed to Rust via FFI: rust_transcription.feedAudio(pcmData, trackId)
    // 4. Receive new TranscriptSegments back
    //
    // The actual audio capture uses flutter_webrtc's MediaRecorder or
    // a custom AudioRenderer to get raw PCM frames.
  }

  void _updateStatus(TranscriptionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void dispose() {
    _processingTimer?.cancel();
    _segmentController.close();
    _statusController.close();
  }
}

/// Transcription engine status.
enum TranscriptionStatus { idle, loading, ready, transcribing, paused, error }
