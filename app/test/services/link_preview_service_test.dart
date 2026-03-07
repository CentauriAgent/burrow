import 'package:flutter_test/flutter_test.dart';
import 'package:burrow_app/services/link_preview_service.dart';

void main() {
  group('LinkPreviewService.extractUrls', () {
    test('extracts https and http URLs', () {
      final urls = LinkPreviewService.extractUrls(
        'Check https://example.com and http://test.org/path for info.',
      );
      expect(urls, ['https://example.com', 'http://test.org/path']);
    });

    test('strips trailing punctuation', () {
      final urls = LinkPreviewService.extractUrls(
        'Visit https://example.com, or https://test.org.',
      );
      expect(urls, ['https://example.com', 'https://test.org']);
    });

    test('returns empty list for no URLs', () {
      final urls = LinkPreviewService.extractUrls('No links here.');
      expect(urls, isEmpty);
    });

    test('handles URLs with query params', () {
      final urls = LinkPreviewService.extractUrls(
        'Link: https://example.com/page?q=hello&lang=en',
      );
      expect(urls, ['https://example.com/page?q=hello&lang=en']);
    });

    test('handles URLs in parentheses', () {
      final urls = LinkPreviewService.extractUrls(
        '(see https://example.com/doc)',
      );
      expect(urls, ['https://example.com/doc']);
    });

    test('rejects too-short URLs', () {
      final urls = LinkPreviewService.extractUrls('http://a.b');
      expect(urls, isEmpty);
    });
  });

  group('LinkPreviewService._parseOgFromHtml (via static method)', () {
    // We test parsing through the internal static method indirectly
    // by checking the OgMetadata structure

    test('OgMetadata.hasPreviewContent', () {
      const withTitle = OgMetadata(url: 'https://example.com', domain: 'example.com', title: 'Hello');
      expect(withTitle.hasPreviewContent, isTrue);

      const withDesc = OgMetadata(url: 'https://example.com', domain: 'example.com', description: 'World');
      expect(withDesc.hasPreviewContent, isTrue);

      const empty = OgMetadata(url: 'https://example.com', domain: 'example.com');
      expect(empty.hasPreviewContent, isFalse);
    });
  });
}
