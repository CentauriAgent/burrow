/// Nostr relay publishing service for call signaling events.
///
/// Bridges between the Rust signaling layer (which creates gift-wrapped events)
/// and the Nostr relay network (which delivers them to the recipient).
library;

import 'dart:async';
import 'dart:convert';
import 'package:burrow_app/src/rust/api/call_signaling.dart'
    as rust_signaling;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// Manages publishing call signaling events to Nostr relays and
/// subscribing to incoming call events.
class NostrSignalingService {
  Timer? _pollTimer;
  final _incomingEventController =
      StreamController<rust_signaling.CallSignalingEvent>.broadcast();

  /// Stream of incoming call signaling events.
  Stream<rust_signaling.CallSignalingEvent> get onSignalingEvent =>
      _incomingEventController.stream;

  /// Publish a gift-wrapped signaling event to connected relays.
  ///
  /// [wrappedEventJson] is the JSON-serialized kind 1059 gift-wrap event
  /// produced by the Rust signaling layer.
  Future<void> publishSignalingEvent(String wrappedEventJson) async {
    // Publish to all configured relays via the Rust relay module
    await rust_relay.publishEventJson(eventJson: wrappedEventJson);
  }

  /// Start listening for incoming call signaling events.
  ///
  /// Subscribes to gift-wrapped events (kind 1059) addressed to the local
  /// user and polls periodically for new events.
  Future<void> startListening() async {
    // Get subscription filter from Rust
    final filterJson = await rust_signaling.subscribeCallEvents();

    // Subscribe via relay module
    await rust_relay.subscribe(filterJson: filterJson);

    // Poll for incoming events every 500ms
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      await _pollForEvents();
    });
  }

  /// Stop listening for incoming events.
  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollForEvents() async {
    try {
      // Fetch new gift-wrapped events from the relay module
      final events = await rust_relay.fetchPendingEvents();

      for (final eventJson in events) {
        // Attempt to unwrap and process as call signaling
        final callEvent =
            await rust_signaling.processCallEvent(eventJson: eventJson);
        if (callEvent != null) {
          _incomingEventController.add(callEvent);
        }
      }
    } catch (_) {
      // Silently handle polling errors — relay may be temporarily unavailable
    }
  }

  /// Dispose resources.
  Future<void> dispose() async {
    stopListening();
    await _incomingEventController.close();
  }
}
