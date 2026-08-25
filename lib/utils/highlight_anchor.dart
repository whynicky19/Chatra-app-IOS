import '../models/annotation.dart';
import 'pdf_text_sanitize.dart';

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

final _space = RegExp(r'\s');

/// Текст без пробелов + карта «символ → его индекс в исходном тексте».
///
/// Весь поиск идёт по сжатому тексту: пробелы — единственное, в чём рендереры
/// расходятся всегда (PDFium ставит перенос там, где текстовый слой pdf.js на
/// сайте не ставит ничего, и наоборот), а карта возвращает найденное обратно в
/// смещения исходного текста страницы.
class _Squashed {
  final String text;
  final List<int> map;
  const _Squashed(this.text, this.map);
}

_Squashed _squashIndexed(String s) {
  final buf = StringBuffer();
  final map = <int>[];
  for (var i = 0; i < s.length; i++) {
    if (_space.hasMatch(s[i])) continue;
    buf.write(s[i]);
    map.add(i);
  }
  return _Squashed(buf.toString(), map);
}

List<int> _hitsOf(String haystack, String needle) {
  final out = <int>[];
  if (needle.isEmpty) return out;
  for (var i = haystack.indexOf(needle); i != -1; i = haystack.indexOf(needle, i + 1)) {
    out.add(i);
  }
  return out;
}

/// Находит фрагмент [a] в [text]. null — если не нашёлся вовсе (тогда пометку
/// просто не рисуем, а не ставим наугад в чужое место).
TextMatch? locateAnnotation(String text, Annotation a) {
  // PDFium отдаёт символы без Unicode-маппинга (бюллетени из Word и т.п.) как
  // U+FFFD. Старые пометки сохранены с «ромбами», новые — с чисткой; заменяем
  // 1:1 с обеих сторон сравнения, чтобы сходились и те, и другие.
  text = sanitizePdfSymbols(text);
  final expected = sanitizePdfSymbols(a.selectedText);
  if (expected.isEmpty || text.isEmpty) return null;

  // 1. По смещениям — если там ровно тот же текст (с точностью до пробелов).
  if (a.endOffset > a.startOffset && a.endOffset <= text.length) {
    final atOffsets = text.substring(a.startOffset, a.endOffset);
    if (_squash(atOffsets) == _squash(expected)) {
      return TextMatch(a.startOffset, a.endOffset);
    }
  }

  final body = _squash(expected);
  if (body.isEmpty) return null;
  final hay = _squashIndexed(text);
  TextMatch back(int from, int to) =>
      TextMatch(hay.map[from], hay.map[to - 1] + 1);

  // 2. По якорю: соседний текст отличает одинаковые фразы друг от друга. Если
  // якорь целиком не сошёлся (фрагмент у края страницы, сосед перерисован
  // иначе) — пробуем половинками, это точнее, чем один голый текст.
  final prefix = _squash(sanitizePdfSymbols(a.prefix));
  final suffix = _squash(sanitizePdfSymbols(a.suffix));
  for (final pair in [[prefix, suffix], [prefix, ''], ['', suffix]]) {
    final head = pair[0], tail = pair[1];
    if (head.isEmpty && tail.isEmpty) continue;
    final hits = _hitsOf(hay.text, '$head$body$tail');
    if (hits.isEmpty) continue;
    return back(hits.first + head.length, hits.first + head.length + body.length);
  }

  // 3. Просто по тексту — ближайшее к исходному месту вхождение.
  final hits = _hitsOf(hay.text, body);
  if (hits.isEmpty) return null;
  final best = hits.reduce((b, i) =>
      (hay.map[i] - a.startOffset).abs() < (hay.map[b] - a.startOffset).abs() ? i : b);
  return back(best, best + body.length);
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
