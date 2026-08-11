import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/dates.dart';
import '../../widgets/tappable.dart';

/// grade.criteria_scores приходит с бэка JSON-строкой (Text-колонка в БД),
/// а не готовым списком — элементы вида {name, score, max, comment}.
List<dynamic> parseCriteriaScores(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw;
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
    } catch (_) {}
  }
  return [];
}

String cleanPostTitle(String t) =>
    t.replaceFirst(RegExp(r'^\[(LECTURE|HW)\]\[\d+\]\s*'), '').trim();

String fmtDate(String? d) {
  final dt = parseServerDate(d);
  if (dt == null) return d ?? '';
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}

// Обязана понимать подпись ?exp=&sig= — иначе подписанные ссылки не видны как вложения.
//
// Хост (`[^\s/]+`) отдельно от пути (`[^\n"<>]*?`) — раньше вся ссылка целиком
// была одним "без пробелов" куском, и если бэкенд возвращал путь с "сырым"
// (не percent-encoded) пробелом в имени файла (бывает — см. encodeUploadedFileUrl
// в этом же файле, где мы теперь это чиним на загрузке), regex переставал
// матчить ссылку целиком, и она оставалась видна в тексте как есть. Пробелы
// в ХОСТЕ невозможны в принципе, поэтому там ограничение осталось прежним —
// это не ослабляет матчинг, просто путь после первого "/" уже терпит пробелы.
final RegExp fileUrlRe = RegExp(
    r'https?://[^\s/]+/[^\n"<>]*?\.(pdf|docx?|pptx?|xlsx?|txt|md|csv|rtf|png|jpe?g|gif|webp|mp3|wav|m4a|webm|ogg|mp4)'
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

/// Бэкенд иногда отдаёт путь загруженного файла с "сырыми" (не
/// percent-encoded) пробелами в имени — например
/// `.../attachments/Laboratory work No 1.docx?exp=...&sig=...`. Такой URL
/// не проходит по `fileUrlRe`/`mdFileRe` при последующей чистке описания
/// (обе регулярки требуют "\S+" до расширения) и остаётся виден пользователю
/// как обычный текст прямо в теле задания/лекции. Кодируем ТОЛЬКО сегмент
/// имени файла — часть между последним "/" и началом query ("?") — не
/// трогая scheme/host/уже закодированный query со ?exp=&sig=.
String encodeUploadedFileUrl(String rawUrl) {
  final qIdx = rawUrl.indexOf('?');
  final head = qIdx == -1 ? rawUrl : rawUrl.substring(0, qIdx);
  final tail = qIdx == -1 ? '' : rawUrl.substring(qIdx);
  final slashIdx = head.lastIndexOf('/');
  if (slashIdx == -1) return rawUrl;
  final dir = head.substring(0, slashIdx + 1);
  final name = head.substring(slashIdx + 1);
  // Уже закодированное имя (нет пробелов/спецсимволов) кодировать повторно
  // не нужно — Uri.encodeComponent на "%20" превратил бы его в "%2520".
  if (RegExp(r'^[A-Za-z0-9._~%-]*$').hasMatch(name)) return rawUrl;
  return '$dir${Uri.encodeComponent(name)}$tail';
}

/// Путь файла без query (?exp=&sig=) и #fragment — подпись сервер выдаёт
/// заново на КАЖДЫЙ ответ (см. file_urls.py: sign_uploads_in_text), поэтому
/// полный URL с подписью нельзя использовать как ключ карты между двумя
/// независимыми вычислениями (например _loadFileTexts и _recomputeAiContext):
/// один и тот же файл получит разные ?exp=&sig= и ключи не совпадут, даже
/// если текст успешно загружен.
String stableFileKey(String url) => cleanFileUrl(url).split('?').first;

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
            child: Tappable(
              onTap: () => Navigator.pop(ctx),
              label: 'Закрыть просмотр изображения',
              child: Container(width: 36, height: 36,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.xmark, color: Colors.white, size: 18)),
            )),
          Positioned(bottom: MediaQuery.of(ctx).padding.bottom + 16, left: 0, right: 0,
            child: Center(child: Text(name, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))),
        ]),
      ),
    ),
  );
}
