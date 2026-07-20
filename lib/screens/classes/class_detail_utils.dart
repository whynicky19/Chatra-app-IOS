import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Pure helpers extracted from class_detail_screen.dart — no widget state, so
// they live here as top-level functions to keep the screen file focused.

/// Strips the '[LECTURE][id] ' / '[HW][id] ' prefix from a post title.
String cleanPostTitle(String t) =>
    t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();

/// Formats an ISO date string as dd.mm.yyyy (falls back to the raw string).
String fmtDate(String? d) {
  if (d == null) return '';
  try {
    final dt = DateTime.parse(d);
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  } catch (_) {
    return d;
  }
}

// Bare uploaded-file URL, optionally with #OriginalName fragment appended by the
// clients. Trailing lookahead pins the match to the token end so ".docx" can't be
// eaten as ".doc"+junk.
final RegExp fileUrlRe = RegExp(
    r'https?://[^\s"<>]+\.(pdf|docx?|txt|md|png|jpe?g|gif|webp|pptx?|xlsx?)(#[^\s"<>]*)?(?![^\s"<>])',
    caseSensitive: false);
// Site-generated markdown attachment: "📎 [name](url)"
final RegExp mdFileRe = RegExp(r'📎\s*\[([^\]\n]+)\]\((https?://[^\s)]+)\)');

/// Removes raw file URLs from content for cleaner display.
String cleanContent(String content) {
  return content
      .replaceAll(mdFileRe, '')
      .replaceAll(fileUrlRe, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// Human-readable filename: uses the URL fragment (#OriginalName.pdf) if present,
/// otherwise falls back to the last path segment (which may be a UUID).
String fileDisplayName(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
    return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
  } catch (_) {
    return url;
  }
}

/// Strips the #fragment from a URL before passing it to launchUrl or fetching.
String cleanFileUrl(String url) {
  final idx = url.indexOf('#');
  return idx >= 0 ? url.substring(0, idx) : url;
}

/// Stable cache key for a remote file.
///
/// Uploads carry a signed query (`?exp=…&sig=…`) that the backend regenerates on
/// every JSON response, so hashing the full URL yields a different key each time:
/// the temp copy is never reused and a fresh duplicate piles up on every open.
/// Only the path identifies the file — upload names are UUIDs and immutable.
String fileCacheKey(String url) {
  try {
    return Uri.parse(url).path.hashCode.toRadixString(16);
  } catch (_) {
    return cleanFileUrl(url).split('?').first.hashCode.toRadixString(16);
  }
}

/// Fullscreen, pinch-to-zoom image viewer (tap anywhere to dismiss).
void showImageViewer(BuildContext ctx, String url, String name) {
  showDialog(
    context: ctx,
    barrierColor: Colors.black87,
    builder: (_) => GestureDetector(
      onTap: () => Navigator.pop(ctx),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          Center(child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              fadeOutDuration: Duration.zero,
              placeholder: (_, __) => Center(child: CircularProgressIndicator(color: Theme.of(ctx).colorScheme.primary, strokeWidth: 2)),
              errorWidget: (_, __, ___) => const Icon(CupertinoIcons.photo, color: Colors.white54, size: 64),
            ),
          )),
          Positioned(top: MediaQuery.of(ctx).padding.top + 8, right: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 18)),
            )),
          Positioned(bottom: MediaQuery.of(ctx).padding.bottom + 16, left: 0, right: 0,
            child: Center(child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis))),
        ]),
      ),
    ),
  );
}
