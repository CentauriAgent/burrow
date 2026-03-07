import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Open Graph metadata extracted from a URL.
class OgMetadata {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final String? siteName;
  final String domain;
  final String? ogType;

  const OgMetadata({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.siteName,
    required this.domain,
    this.ogType,
  });

  /// Whether this metadata has enough content to show a preview card.
  bool get hasPreviewContent => title != null || description != null;
}

/// Service for fetching and caching link preview metadata.
///
/// Uses an in-memory LRU-style cache to avoid re-fetching the same URL.
/// Fetches are limited to 256KB of HTML and have a 10-second timeout.
class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  /// In-memory cache: URL → metadata (or null if fetch failed).
  final Map<String, OgMetadata?> _cache = {};

  /// In-flight requests to avoid duplicate fetches for the same URL.
  final Map<String, Future<OgMetadata?>> _pending = {};

  /// Maximum number of cached entries.
  static const int _maxCacheSize = 200;

  /// Fetch OG metadata for a URL, using cache if available.
  Future<OgMetadata?> fetchMetadata(String url) async {
    // Check cache first
    if (_cache.containsKey(url)) {
      return _cache[url];
    }

    // Check if there's already a fetch in progress for this URL
    if (_pending.containsKey(url)) {
      return _pending[url];
    }

    // Start a new fetch
    final future = _doFetch(url);
    _pending[url] = future;

    try {
      final result = await future;
      _addToCache(url, result);
      return result;
    } catch (_) {
      _addToCache(url, null);
      return null;
    } finally {
      _pending.remove(url);
    }
  }

  /// Clear the cache.
  void clearCache() {
    _cache.clear();
    _pending.clear();
  }

  /// Extract URLs from a text string.
  static List<String> extractUrls(String text) {
    final urls = <String>[];
    for (final word in text.split(RegExp(r'\s+'))) {
      // Strip trailing punctuation
      var cleaned = word;
      while (cleaned.isNotEmpty &&
          RegExp(r'[,.\)\]>;!?]$').hasMatch(cleaned) &&
          !cleaned.endsWith('...')) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
      if ((cleaned.startsWith('https://') || cleaned.startsWith('http://')) &&
          cleaned.length > 10) {
        urls.add(cleaned);
      }
    }
    return urls;
  }

  void _addToCache(String url, OgMetadata? metadata) {
    // Evict oldest entries if cache is full
    if (_cache.length >= _maxCacheSize) {
      final keysToRemove = _cache.keys.take(_cache.length - _maxCacheSize + 1).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
    _cache[url] = metadata;
  }

  Future<OgMetadata?> _doFetch(String url) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5)
        ..idleTimeout = const Duration(seconds: 10);

      final uri = Uri.parse(url);
      final request = await client.getUrl(uri).timeout(
        const Duration(seconds: 5),
      );
      request.headers.set('User-Agent', 'Burrow/1.0 (Link Preview)');
      request.headers.set('Accept', 'text/html,application/xhtml+xml');
      request.followRedirects = true;
      request.maxRedirects = 5;

      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );

      // Check content type
      final contentType =
          response.headers.contentType?.toString().toLowerCase() ?? '';
      if (!contentType.contains('text/html') &&
          !contentType.contains('application/xhtml')) {
        client.close(force: true);
        return OgMetadata(
          url: url,
          domain: _extractDomain(url),
        );
      }

      // Read up to 256KB
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 256 * 1024) break;
      }
      client.close(force: true);

      final html = utf8.decode(bytes, allowMalformed: true);
      return _parseOgFromHtml(html, url);
    } on TimeoutException {
      return null;
    } on SocketException {
      return null;
    } on HttpException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parse OG metadata from HTML.
  static OgMetadata _parseOgFromHtml(String html, String url) {
    String? ogTitle;
    String? ogDescription;
    String? ogImage;
    String? ogSiteName;
    String? ogType;
    String? htmlTitle;
    String? metaDescription;

    final htmlLower = html.toLowerCase();

    // Extract <title>
    final titleMatch =
        RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true).firstMatch(htmlLower);
    if (titleMatch != null) {
      final start = titleMatch.start + html.substring(titleMatch.start).indexOf('>') + 1;
      final end = html.toLowerCase().indexOf('</title', start);
      if (end > start) {
        final t = html.substring(start, end).trim();
        if (t.isNotEmpty) htmlTitle = _decodeHtmlEntities(t);
      }
    }

    // Extract <meta> tags
    final metaRegex = RegExp(
      r'<meta\s[^>]*?>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in metaRegex.allMatches(html)) {
      final tag = match.group(0)!;
      final property = _extractAttr(tag, 'property') ?? _extractAttr(tag, 'name');
      final content = _extractAttr(tag, 'content');

      if (property == null || content == null) continue;
      final prop = property.toLowerCase();
      final cont = _decodeHtmlEntities(content);

      switch (prop) {
        case 'og:title':
          ogTitle = cont;
          break;
        case 'og:description':
          ogDescription = _truncate(cont, 300);
          break;
        case 'og:image':
          ogImage = cont;
          break;
        case 'og:site_name':
          ogSiteName = cont;
          break;
        case 'og:type':
          ogType = cont;
          break;
        case 'description':
        case 'twitter:description':
          metaDescription ??= _truncate(cont, 300);
          break;
        case 'twitter:title':
          ogTitle ??= cont;
          break;
        case 'twitter:image':
        case 'twitter:image:src':
          ogImage ??= cont;
          break;
      }
    }

    // Fallbacks
    ogTitle ??= htmlTitle;
    ogDescription ??= metaDescription;

    // Resolve relative image URLs
    if (ogImage != null) {
      if (ogImage!.startsWith('/') && !ogImage!.startsWith('//')) {
        final scheme = url.startsWith('https') ? 'https' : 'http';
        ogImage = '$scheme://${_extractDomain(url)}$ogImage';
      } else if (ogImage!.startsWith('//')) {
        ogImage = 'https:$ogImage';
      }
    }

    return OgMetadata(
      url: url,
      title: ogTitle,
      description: ogDescription,
      imageUrl: ogImage,
      siteName: ogSiteName,
      domain: _extractDomain(url),
      ogType: ogType,
    );
  }

  static String _extractDomain(String url) {
    return Uri.tryParse(url)?.host ?? url;
  }

  static String? _extractAttr(String tag, String attrName) {
    // Try double quotes
    final dqPattern = RegExp(
      '${RegExp.escape(attrName)}\\s*=\\s*"([^"]*)"',
      caseSensitive: false,
    );
    final dqMatch = dqPattern.firstMatch(tag);
    if (dqMatch != null) return dqMatch.group(1);

    // Try single quotes
    final sqPattern = RegExp(
      "${RegExp.escape(attrName)}\\s*=\\s*'([^']*)'",
      caseSensitive: false,
    );
    final sqMatch = sqPattern.firstMatch(tag);
    if (sqMatch != null) return sqMatch.group(1);

    return null;
  }

  static String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&nbsp;', ' ');
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen - 1)}…';
  }
}
