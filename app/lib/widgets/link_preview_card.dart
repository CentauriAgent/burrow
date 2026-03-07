import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:burrow_app/services/link_preview_service.dart';

/// A compact card showing Open Graph metadata for a URL.
///
/// Displays: thumbnail image (if available), title, description (truncated),
/// and domain name. Tapping the card opens the URL in the system browser.
///
/// Gracefully degrades: if OG fetch fails, nothing is shown (the URL text
/// in the message body remains clickable via Markdown rendering).
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool isSent;

  const LinkPreviewCard({
    super.key,
    required this.url,
    this.isSent = false,
  });

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  OgMetadata? _metadata;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    try {
      final metadata =
          await LinkPreviewService.instance.fetchMetadata(widget.url);
      if (mounted) {
        setState(() {
          _metadata = metadata;
          _loading = false;
          _failed = metadata == null || !metadata.hasPreviewContent;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Don't show anything while loading or if fetch failed
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }

    if (_failed || _metadata == null || !_metadata!.hasPreviewContent) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final meta = _metadata!;

    // Card colors based on sent/received
    final cardColor = widget.isSent
        ? theme.colorScheme.primary.withAlpha(40)
        : theme.colorScheme.surfaceContainerHigh;
    final titleColor = widget.isSent
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;
    final descColor = widget.isSent
        ? theme.colorScheme.onPrimary.withAlpha(180)
        : theme.colorScheme.onSurface.withAlpha(160);
    final domainColor = widget.isSent
        ? theme.colorScheme.onPrimary.withAlpha(140)
        : theme.colorScheme.onSurface.withAlpha(120);

    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(meta.url)),
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outline.withAlpha(30),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Thumbnail image
            if (meta.imageUrl != null)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 150,
                ),
                child: Image.network(
                  meta.imageUrl!,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 80,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    );
                  },
                ),
              ),

            // Text content
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Domain / site name
                  Row(
                    children: [
                      Icon(
                        Icons.link,
                        size: 12,
                        color: domainColor,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          meta.siteName ?? meta.domain,
                          style: TextStyle(
                            fontSize: 11,
                            color: domainColor,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // Title
                  if (meta.title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta.title!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // Description
                  if (meta.description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: descColor,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
