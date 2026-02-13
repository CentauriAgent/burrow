/// Nostr relay signaling service for call events.
///
/// Bridges the Rust call signaling layer with the Dart CallManager:
/// - Subscribes to incoming gift-wrapped call events via Rust stream
/// - Publishes outgoing gift-wrapped events to connected relays
library;

import 'dart:async';
import 'package:burrow_app/src/rust/api/call_signaling.dart' as rust_signaling;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

class NostrSignalingService {
  StreamSubscription<rust_signaling.CallSignalingEvent>? _subscription;
  final _incomingEventController =
      StreamController<rust_signaling.CallSignalingEvent>.broadcast();

  /// Stream of incoming call signaling events (unwrapped from gift-wraps).
  Stream<rust_signaling.CallSignalingEvent> get onSignalingEvent =>
      _incomingEventController.stream;

  /// Publish a gift-wrapped signaling event to connected relays.
  Future<void> publishSignalingEvent(String wrappedEventJson) async {
    await rust_relay.publishEventJson(eventJson: wrappedEventJson);
  }

  /// Start listening for incoming call signaling events.
  ///
  /// Subscribes to the Rust stream that handles:
  /// 1. Subscribing to kind 1059 (GiftWrap) events on connected relays
  /// 2. Unwrapping NIP-59 gift wraps using the local key
  /// 3. Parsing call signaling kinds (25050-25054)
  Future<void> startListening() async {
    // Avoid double subscription
    await stopListening();

    _subscription = rust_signaling.listenForCallEvents().listen(
      (event) {
        _incomingEventController.add(event);
      },
      onError: (error) {
        // Stream error — relay disconnected or similar
        // Will be restarted on next startListening() call
      },
    );
  }

  /// Stop listening for incoming events.
  Future<void> stopListening() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await stopListening();
    await _incomingEventController.close();
  }
}
