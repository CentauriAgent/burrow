import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/models/transcript.dart';
import 'package:burrow_app/services/transcription_service.dart';

/// State for real-time transcription during a call.
class TranscriptionState {
  final TranscriptionStatus status;
  final List<TranscriptSegment> segments;
  final String? callId;
  final String? searchQuery;
  final List<TranscriptSegment> searchResults;
  final bool showLiveTranscript;

  const TranscriptionState({
    this.status = TranscriptionStatus.idle,
    this.segments = const [],
    this.callId,
    this.searchQuery,
    this.searchResults = const [],
    this.showLiveTranscript = true,
  });

  TranscriptionState copyWith({
    TranscriptionStatus? status,
    List<TranscriptSegment>? segments,
    String? callId,
    String? searchQuery,
    List<TranscriptSegment>? searchResults,
    bool? showLiveTranscript,
  }) {
    return TranscriptionState(
      status: status ?? this.status,
      segments: segments ?? this.segments,
      callId: callId ?? this.callId,
      searchQuery: searchQuery ?? this.searchQuery,
      searchResults: searchResults ?? this.searchResults,
      showLiveTranscript: showLiveTranscript ?? this.showLiveTranscript,
    );
  }

  bool get isActive => status == TranscriptionStatus.transcribing;
  bool get isPaused => status == TranscriptionStatus.paused;
  int get segmentCount => segments.length;
}

class TranscriptionNotifier extends Notifier<TranscriptionState> {
  late final TranscriptionService _service;
  final List<StreamSubscription> _subscriptions = [];

  @override
  TranscriptionState build() {
    _service = TranscriptionService();

    _subscriptions.add(
      _service.onSegment.listen(_handleNewSegment),
    );
    _subscriptions.add(
      _service.onStatus.listen(_handleStatusChange),
    );

    ref.onDispose(() {
      for (final sub in _subscriptions) {
        sub.cancel();
      }
      _service.dispose();
    });

    return const TranscriptionState();
  }

  /// Initialize the transcription engine.
  Future<void> initialize({TranscriptionConfig? config}) async {
    await _service.initialize(config: config ?? const TranscriptionConfig());
  }

  /// Start transcription for an active call.
  Future<void> startTranscription({required String callId}) async {
    await _service.startTranscription(callId: callId);
    state = state.copyWith(callId: callId);
  }

  /// Register a speaker (maps WebRTC track to identity).
  void registerSpeaker({
    required String trackId,
    required String pubkeyHex,
    required String displayName,
  }) {
    _service.registerSpeaker(
      trackId: trackId,
      pubkeyHex: pubkeyHex,
      displayName: displayName,
    );
  }

  /// Pause/resume transcription.
  void togglePause() {
    if (state.isActive) {
      _service.pause();
    } else if (state.isPaused) {
      _service.resume();
    }
  }

  /// Stop transcription and return segments.
  Future<List<TranscriptSegment>> stopTranscription() async {
    return await _service.stopTranscription();
  }

  /// Search transcript.
  void search(String query) {
    if (query.isEmpty) {
      state = state.copyWith(
        searchQuery: '',
        searchResults: [],
      );
    } else {
      final results = _service.search(query);
      state = state.copyWith(
        searchQuery: query,
        searchResults: results,
      );
    }
  }

  /// Toggle live transcript visibility.
  void toggleLiveTranscript() {
    state = state.copyWith(showLiveTranscript: !state.showLiveTranscript);
  }

  /// Get formatted transcript text.
  String getFormattedTranscript() => _service.getFormattedTranscript();

  /// Get segments as JSON for meeting notes generation.
  String getSegmentsJson() => _service.getSegmentsJson();

  void _handleNewSegment(TranscriptSegment segment) {
    state = state.copyWith(
      segments: [...state.segments, segment],
    );
  }

  void _handleStatusChange(TranscriptionStatus status) {
    state = state.copyWith(status: status);
  }
}

final transcriptionProvider =
    NotifierProvider<TranscriptionNotifier, TranscriptionState>(() {
  return TranscriptionNotifier();
});
