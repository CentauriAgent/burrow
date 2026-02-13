/// E2EE frame encryption service for WebRTC media streams.
///
/// Wraps flutter_webrtc's FrameCryptor API to provide end-to-end encryption
/// of media frames using keys derived from MLS exporter_secret (via Rust core).
///
/// Used in SFU mode where DTLS-SRTP terminates at the SFU — frame-level
/// encryption ensures the SFU cannot access media content.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:burrow_app/src/rust/api/call_webrtc.dart' as rust_webrtc;

/// Manages frame-level encryption for WebRTC media streams.
class FrameEncryptionService {
  final Map<String, FrameCryptor> _senderCryptors = {};
  final Map<String, FrameCryptor> _receiverCryptors = {};
  KeyProvider? _keyProvider;
  String? _currentKeyHex;

  /// Whether frame encryption is currently active.
  bool get isActive => _keyProvider != null;

  /// Initialize frame encryption with a key derived from MLS exporter_secret.
  ///
  /// [exporterSecretHex] - MLS exporter_secret (hex-encoded).
  /// [callId] - Unique call identifier for key derivation context.
  Future<void> initialize({
    required String exporterSecretHex,
    required String callId,
  }) async {
    // Derive frame encryption key via Rust
    _currentKeyHex = await rust_webrtc.deriveFrameEncryptionKey(
      exporterSecretHex: exporterSecretHex,
      callId: callId,
    );

    // Create key provider with the derived key
    _keyProvider = await frameCryptorFactory.createDefaultKeyProvider(
      KeyProviderOptions(
        sharedKey: true,
        ratchetSalt: utf8.encode(callId),
        ratchetWindowSize: 16,
      ),
    );

    // Set the shared key
    final keyBytes = _hexToBytes(_currentKeyHex!);
    await _keyProvider!.setSharedKey(key: keyBytes);
  }

  /// Enable frame encryption on all senders of a peer connection.
  Future<void> encryptSenders(RTCPeerConnection pc, String peerId) async {
    if (_keyProvider == null) return;

    final senders = await pc.getSenders();
    for (final sender in senders) {
      if (sender.track == null) continue;

      final cryptor = await frameCryptorFactory.createFrameCryptorForRtpSender(
        participantId: peerId,
        sender: sender,
        algorithm: Algorithm.kAesGcm,
        keyProvider: _keyProvider!,
      );
      await cryptor.setEnabled(true);
      _senderCryptors[peerId] = cryptor;
    }
  }

  /// Enable frame decryption on all receivers of a peer connection.
  Future<void> decryptReceivers(RTCPeerConnection pc, String peerId) async {
    if (_keyProvider == null) return;

    final receivers = await pc.getReceivers();
    for (final receiver in receivers) {
      if (receiver.track == null) continue;

      final cryptor =
          await frameCryptorFactory.createFrameCryptorForRtpReceiver(
        participantId: peerId,
        receiver: receiver,
        algorithm: Algorithm.kAesGcm,
        keyProvider: _keyProvider!,
      );
      await cryptor.setEnabled(true);
      _receiverCryptors[peerId] = cryptor;
    }
  }

  /// Rotate the frame encryption key (called when MLS epoch changes).
  ///
  /// [newEpoch] - The new MLS epoch number.
  /// [callId] - Call identifier for context binding.
  Future<void> rotateKey({
    required int newEpoch,
    required String callId,
  }) async {
    if (_keyProvider == null || _currentKeyHex == null) return;

    // Derive new key via Rust key rotation
    _currentKeyHex = await rust_webrtc.rotateFrameKey(
      currentKeyHex: _currentKeyHex!,
      newEpoch: BigInt.from(newEpoch),
      callId: callId,
    );

    // Update the shared key — FrameCryptor handles the ratchet window
    final keyBytes = _hexToBytes(_currentKeyHex!);
    await _keyProvider!.setSharedKey(key: keyBytes);
  }

  /// Disable and clean up all frame encryption.
  Future<void> dispose() async {
    for (final cryptor in _senderCryptors.values) {
      await cryptor.setEnabled(false);
      await cryptor.dispose();
    }
    for (final cryptor in _receiverCryptors.values) {
      await cryptor.setEnabled(false);
      await cryptor.dispose();
    }
    _senderCryptors.clear();
    _receiverCryptors.clear();
    _keyProvider = null;
    _currentKeyHex = null;
  }

  Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }
}
