import '../models/annotation.dart';

/// Поиск сохранённого выделения в тексте, который сейчас на экране.
///
/// Смещения — основной путь: если по ним лежит тот же текст, ставим пометку
/// туда. Но выделение могло быть сделано на другом клиенте (PDF на сайте
/// разбирает pdf.js, здесь — PDFium, и потоки текста у них расходятся в
/// пробелах и переносах), поэтому есть запасной путь по якорю
/// prefix + текст + suffix — как на сайте (composables/useTextHighlighter.ts).
class TextMatch {
  final int start;
  final int end;
  const TextMatch(this.start, this.end);
}

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), '');

String _looseEscape(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map(RegExp.escape).join(r'\s*');

/// Находит фрагмент [a] в [text]. null — если не нашёлся вовсе (тогда пометку
/// просто не рисуем, а не ставим наугад в чужое место).
TextMatch? locateAnnotation(String text, Annotation a) {
  final expected = a.selectedText;
  if (expected.isEmpty || text.isEmpty) return null;

  // 1. По смещениям — если там ровно тот же текст (с точностью до пробелов).
  if (a.endOffset > a.startOffset && a.endOffset <= text.length) {
    final atOffsets = text.substring(a.startOffset, a.endOffset);
    if (_squash(atOffsets) == _squash(expected)) {
      return TextMatch(a.startOffset, a.endOffset);
    }
  }

  final body = _looseEscape(expected);
  if (body.isEmpty) return null;

  // 2. По якорю: соседний текст отличает одинаковые фразы друг от друга.
  final prefix = a.prefix.trim();
  final suffix = a.suffix.trim();
  if (prefix.isNotEmpty || suffix.isNotEmpty) {
    final head = prefix.isNotEmpty ? '(${_looseEscape(prefix)}\\s*)' : '';
    final tail = suffix.isNotEmpty ? '(?:\\s*${_looseEscape(suffix)})' : '';
    final pattern = '$head($body)$tail';
    final m = RegExp(pattern).firstMatch(text);
    if (m != null) {
      final skip = prefix.isNotEmpty ? m.group(1)!.length : 0;
      final matched = prefix.isNotEmpty ? m.group(2)! : m.group(1)!;
      return TextMatch(m.start + skip, m.start + skip + matched.length);
    }
  }

  // 3. Просто по тексту — ближайшее к исходному месту вхождение.
  TextMatch? best;
  for (final m in RegExp(body).allMatches(text)) {
    final candidate = TextMatch(m.start, m.end);
    if (best == null ||
        (candidate.start - a.startOffset).abs() < (best.start - a.startOffset).abs()) {
      best = candidate;
    }
  }
  return best;
}

/// Текст вокруг выделения — сохраняется вместе с ним как якорь.
({String prefix, String suffix}) anchorAround(String text, int start, int end, {int chars = 60}) => (
      prefix: text.substring((start - chars).clamp(0, start), start),
      suffix: text.substring(end.clamp(0, text.length), (end + chars).clamp(end, text.length)),
    );

/// Расширяет выделение до целых слов и убирает пробелы по краям.
///
/// Просмотрщик отдаёт выделение ровно по символам, на которые попал палец, —
/// из-за этого пометка обрывалась на половине слова. В приложениях Apple
/// выделение всегда прилипает к словам, здесь то же самое делается перед
/// сохранением.
({int start, int end}) snapToWords(String text, int start, int end) {
  if (text.isEmpty) return (start: start, end: end);
  var s = start.clamp(0, text.length);
  var e = end.clamp(0, text.length);
  if (e <= s) return (start: s, end: e);

  bool isWord(int i) => i >= 0 && i < text.length && _wordChar.hasMatch(text[i]);

  // Пробелы по краям в пометку не тащим.
  while (s < e && !isWord(s) && _space.hasMatch(text[s])) {
    s++;
  }
  while (e > s && !isWord(e - 1) && _space.hasMatch(text[e - 1])) {
    e--;
  }
  // Начали/кончили посреди слова — дотягиваем до его границы.
  while (s > 0 && isWord(s) && isWord(s - 1)) {
    s--;
  }
  while (e < text.length && isWord(e - 1) && isWord(e)) {
    e++;
  }
  return (start: s, end: e);
}

final _wordChar = RegExp(r'[\p{L}\p{N}_]', unicode: true);
final _space = RegExp(r'\s');
