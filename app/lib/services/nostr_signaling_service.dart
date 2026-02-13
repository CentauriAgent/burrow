/// Nostr relay publishing service for call signaling events.
///
/// Bridges between the Rust signaling layer (which creates gift-wrapped events)
/// and the Nostr relay network (which delivers them to the recipient).
library;

import 'dart:async';
import 'package:burrow_app/src/rust/api/call_signaling.dart' as rust_signaling;
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
    // TODO: Implement relay subscription when relay subscriptions are wired up.
    // For now this is a no-op — call event delivery requires relay subscription
    // support in the Rust layer.
  }

  /// Stop listening for incoming events.
  void stopListening() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    stopListening();
    await _incomingEventController.close();
  }
}
