import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:burrow_app/src/rust/api/media.dart' as rust_media;
import 'package:burrow_app/src/rust/api/message.dart' as rust_message;
import 'package:burrow_app/src/rust/api/group.dart' as rust_group;
import 'package:burrow_app/src/rust/api/relay.dart' as rust_relay;

/// Parsed media attachment from a message's imeta tag.
class MediaAttachment {
  final String url;
  final String mimeType;
  final String filename;
  final String originalHashHex;
  final String nonceHex;
  final String schemeVersion;
  final String? dimensions;

  MediaAttachment({
    required this.url,
    required this.mimeType,
    required this.filename,
    required this.originalHashHex,
    required this.nonceHex,
    required this.schemeVersion,
    this.dimensions,
  });

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isAudio => mimeType.startsWith('audio/');
  bool get isFile => !isImage && !isVideo && !isAudio;
}

/// Service for sending and receiving encrypted media attachments (MIP-04 v2).
class MediaAttachmentService {
  static final _imagePicker = ImagePicker();
  static String? _cachePath;

  static Future<String> _getCachePath() async {
    if (_cachePath != null) return _cachePath!;
    final dir = await getApplicationSupportDirectory();
    _cachePath = '${dir.path}/media_cache';
    await Directory(_cachePath!).create(recursive: true);
    return _cachePath!;
  }

  /// Pick a photo from gallery.
  static Future<XFile?> pickPhoto() async {
    return _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
  }

  /// Pick a video from gallery.
  static Future<XFile?> pickVideo() async {
    return _imagePicker.pickVideo(source: ImageSource.gallery);
  }

  /// Pick any file.
  static Future<PlatformFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    return result?.files.firstOrNull;
  }

  /// Upload a media attachment, send a message with the imeta tag, and return
  /// the SendMessageResult. The caller can use the result for immediate UI
  /// display — relay publishing is done here in the background.
  static Future<rust_message.SendMessageResult> sendMediaMessage({
    required String groupId,
    required Uint8List fileData,
    required String mimeType,
    required String filename,
    String content = '',
    String? blossomServerUrl,
  }) async {
    final serverUrl =
        blossomServerUrl ?? await rust_group.defaultBlossomServer();

    // 1. Encrypt + upload to Blossom
    final uploadResult = await rust_media.uploadMedia(
      mlsGroupIdHex: groupId,
      fileData: fileData,
      mimeType: mimeType,
      filename: filename,
      blossomServerUrl: serverUrl,
    );

    // 2. Build message content — use filename as content if no text provided
    final messageContent = content.isNotEmpty ? content : filename;

    // 3. Send message with imeta tag
    final result = await rust_message.sendMessageWithMedia(
      mlsGroupIdHex: groupId,
      content: messageContent,
      imetaTagsJson: [uploadResult.imetaTagValues],
    );

    // 4. Cache the original file locally so sent messages display instantly
    try {
      final cachePath = await _getCachePath();
      final cacheFile = File(
        '$cachePath/${uploadResult.reference.originalHashHex}_$filename',
      );
      if (!cacheFile.existsSync()) {
        await cacheFile.writeAsBytes(fileData);
      }
    } catch (_) {
      // Non-fatal — worst case it re-downloads from Blossom
    }

    // 5. Publish to relays in background
    unawaited(
      rust_relay
          .publishEventJson(eventJson: result.eventJson)
          .catchError((_) => ''),
    );

    return result;
  }

  /// Parse imeta tags from a message's tags list.
  /// Returns a list of MediaAttachment objects.
  static List<MediaAttachment> parseAttachments(List<List<String>> tags) {
    final attachments = <MediaAttachment>[];
    for (final tag in tags) {
      if (tag.isEmpty || tag[0] != 'imeta') continue;

      // Parse the imeta values (everything after "imeta")
      final values = tag.sublist(1);
      String? url, mime, fname, hash, nonce, version, dims;
      for (final v in values) {
        final parts = v.split(' ');
        if (parts.length < 2) continue;
        final key = parts[0];
        final val = parts.sublist(1).join(' ');
        switch (key) {
          case 'url':
            url = val;
          case 'm':
            mime = val;
          case 'filename':
            fname = val;
          case 'x':
            hash = val;
          case 'n':
            nonce = val;
          case 'v':
            version = val;
          case 'dim':
            dims = val;
        }
      }

      if (url != null &&
          mime != null &&
          fname != null &&
          hash != null &&
          nonce != null &&
          version != null) {
        attachments.add(
          MediaAttachment(
            url: url,
            mimeType: mime,
            filename: fname,
            originalHashHex: hash,
            nonceHex: nonce,
            schemeVersion: version,
            dimensions: dims,
          ),
        );
      }
    }
    return attachments;
  }

  /// Download and decrypt a media attachment. Caches locally.
  /// Returns immediately from cache for sent messages (cached during send).
  static Future<File> downloadAttachment({
    required String groupId,
    required MediaAttachment attachment,
  }) async {
    final cachePath = await _getCachePath();
    final cacheFile = File(
      '$cachePath/${attachment.originalHashHex}_${attachment.filename}',
    );

    // Return cached file if exists (includes files we just sent)
    if (cacheFile.existsSync() && cacheFile.lengthSync() > 0) {
      return cacheFile;
    }

    // Download and decrypt from Blossom
    final decrypted = await rust_media.downloadMedia(
      mlsGroupIdHex: groupId,
      url: attachment.url,
      mimeType: attachment.mimeType,
      filename: attachment.filename,
      originalHashHex: attachment.originalHashHex,
      nonceHex: attachment.nonceHex,
      schemeVersion: attachment.schemeVersion,
      dimensions: attachment.dimensions,
    );

    if (decrypted.isEmpty) {
      throw Exception('Decrypted file is empty');
    }

    await cacheFile.writeAsBytes(decrypted);
    return cacheFile;
  }

  /// Guess MIME type from file extension.
  static String guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }
}
