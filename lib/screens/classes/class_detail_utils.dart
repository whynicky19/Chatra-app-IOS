import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

String cleanPostTitle(String t) =>
    t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();

String fmtDate(String? d) {
  if (d == null) return '';
  try {
    final dt = DateTime.parse(d);
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
  } catch (_) {
    return d;
  }
}

// Обязана понимать подпись ?exp=&sig= — иначе подписанные ссылки не видны как вложения.
final RegExp fileUrlRe = RegExp(
    r'https?://[^\s"<>]+?\.(pdf|docx?|pptx?|xlsx?|txt|md|csv|rtf|png|jpe?g|gif|webp|mp3|wav|m4a|webm|ogg|mp4)'
    r'(\?[^\s"<>]*)?(#[^\s"<>]*)?',
    caseSensitive: false);
// URL внутри скобок может содержать пробелы (оригинальное имя файла в пути,
// например "Lection 1.pptx") — границу задают сами скобки markdown-ссылки,
// поэтому пробел из группы захвата не исключаем, только ')' и перевод строки.
final RegExp mdFileRe = RegExp(r'📎\s*\[([^\]\n]+)\]\((https?://[^)\n]+)\)');

String cleanContent(String content) {
  return content
      .replaceAll(mdFileRe, '')
      .replaceAll(fileUrlRe, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String fileDisplayName(String url) {
  try {
    final uri = Uri.parse(url);
    if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
    return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
  } catch (_) {
    return url;
  }
}

String cleanFileUrl(String url) {
  final idx = url.indexOf('#');
  return idx >= 0 ? url.substring(0, idx) : url;
}

// Срезает только непарные скобки: иначе ) из markdown уезжает в sig и ломает подпись (403).
String trimUrlPunctuation(String url) {
  var s = url;
  while (s.isNotEmpty) {
    final last = s[s.length - 1];
    if (last == ')' || last == ']') {
      final open = last == ')' ? '(' : '[';
      if (open.allMatches(s).length >= last.allMatches(s).length) break;
    } else if (!'.,;:!'.contains(last)) {
      break;
    }
    s = s.substring(0, s.length - 1);
  }
  return s;
}

List<String> extractFileUrls(String text) => fileUrlRe
    .allMatches(text)
    .map((m) => trimUrlPunctuation(m.group(0)!))
    .toList();

// Ключ строго от path: подпись меняется в каждом ответе, иначе кэш мёртв и temp растёт.
String fileCacheKey(String url) {
  try {
    return Uri.parse(url).path.hashCode.toRadixString(16);
  } catch (_) {
    return cleanFileUrl(url).split('?').first.hashCode.toRadixString(16);
  }
}

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
