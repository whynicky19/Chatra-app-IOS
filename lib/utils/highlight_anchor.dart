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

/// Канонизация символа при сравнении текста пометки с текстом страницы.
///
/// pdf.js на сайте применяет NFKC-нормализацию к текстовому слою, PDFium в
/// приложении — нет; разные движки по-разному отдают типографику (кавычки,
/// тире, многоточия) и вставляют нулевые символы. Без канонизации сохранённый
/// на сайте фрагмент не находится в тексте страницы ни по смещениям, ни по
/// якорю — пометка видна в списке, но не рисуется (типичный случай: .ppt,
/// сконвертированный LibreOffice в PDF).
///
/// Возвращает null для символов, которые надо выбросить (нулевая ширина),
/// иначе строку-замену (может быть длиннее одного символа — лигатуры).
String? _canonChar(String ch) {
  const skip = {'\u200B', '\u200C', '\u200D', '\uFEFF', '\u00AD'};
  if (skip.contains(ch)) return null;
  const map = {
    // Типографские кавычки и апострофы → один канонический символ.
    '«': '"', '»': '"', '“': '"', '”': '"', '„': '"', '‟': '"',
    '‘': "'", '’': "'", '‚': "'", 'ʼ': "'",
    // Тире/дефисы/минусы → '-'.
    '–': '-', '—': '-', '‑': '-', '‒': '-', '−': '-', '‐': '-',
    '﹣': '-', '－': '-',
    // Многоточие → две точки (одна точка слишком часто ложное совпадение).
    '…': '..',
    // Лиатуры NFKC (pdf.js их раскрывает, PDFium — нет).
    'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬀ': 'ff', 'ﬃ': 'ffi', 'ﬄ': 'ffl',
    // Прочие «похожие» символы.
    'º': 'o', '°': 'o', '\u00A0': ' ',
  };
  final mapped = map[ch];
  // Символ не из таблицы канонизации (обычная буква/цифра) остаётся как есть.
  return mapped ?? ch;
}

/// Канонизированный текст без пробелов.
String _squash(String s) {
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (_space.hasMatch(ch)) continue;
    final c = _canonChar(ch);
    if (c == null) continue;
    buf.write(c);
  }
  return buf.toString();
}

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
    final ch = s[i];
    if (_space.hasMatch(ch)) continue;
    final c = _canonChar(ch);
    if (c == null) continue;
    // Многосимвольная замена (лигатура): каждый выходной символ указывает на
    // тот же исходный индекс — обратный маппинг остаётся корректным.
    buf.write(c);
    map.addAll(List.filled(c.length, i));
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
  final ranges = locateAnnotationRanges(text, a);
  return ranges.isEmpty ? null : ranges.first;
}

/// Все диапазоны пометки в тексте страницы.
///
/// Основной путь тот же, что раньше: смещения → якорь → голый текст. Если
/// фрагмент целиком не нашёлся (типичный случай для .ppt: слайд — это
/// абсолютно позиционированные текст-боксы, LibreOffice пишет их в PDF в
/// своём порядке, pdf.js на сайте отдаёт в порядке потока, а PDFium
/// выстраивает по своим layout-эвристикам — непрерывный на сайте фрагмент в
/// тексте страницы перемешан с соседними боксами), разбиваем сохранённый
/// текст на слова и ищем самую длинную НЕПРЕРЫВНУЮ цепочку слов — рисуем
/// хотя бы её, а не отбрасываем пометку целиком.
List<TextMatch> locateAnnotationRanges(String text, Annotation a) {
  // PDFium отдаёт символы без Unicode-маппинга (бюллетени из Word и т.п.) как
  // U+FFFD. Старые пометки сохранены с «ромбами», новые — с чисткой; заменяем
  // 1:1 с обеих сторон сравнения, чтобы сходились и те, и другие.
  final page = sanitizePdfSymbols(text);
  final expected = sanitizePdfSymbols(a.selectedText);
  if (expected.isEmpty || page.isEmpty) return const [];

  // 1. По смещениям — если там ровно тот же текст (с точностью до пробелов).
  if (a.endOffset > a.startOffset && a.endOffset <= page.length) {
    final atOffsets = page.substring(a.startOffset, a.endOffset);
    if (_squash(atOffsets) == _squash(expected)) {
      return [TextMatch(a.startOffset, a.endOffset)];
    }
  }

  final body = _squash(expected);
  if (body.isEmpty) return const [];
  final hay = _squashIndexed(page);
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
    return [back(hits.first + head.length, hits.first + head.length + body.length)];
  }

  // 3. Просто по тексту — ближайшее к исходному месту вхождение.
  final hits = _hitsOf(hay.text, body);
  if (hits.isNotEmpty) {
    final best = hits.reduce((b, i) =>
        (hay.map[i] - a.startOffset).abs() < (hay.map[b] - a.startOffset).abs() ? i : b);
    return [back(best, best + body.length)];
  }

  // 4. Частичное совпадение: самая длинная непрерывная цепочка слов из
  // сохранённого фрагмента. Порядок текста в слайдах расходится между
  // движками так, что фраза целиком не находится, но слова-то на месте.
  final words = expected
      .split(RegExp(r'\s+'))
      .map(_squash)
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length < 2) return const [];

  final starts = <List<int>>[
    for (final w in words) _hitsOf(hay.text, w),
  ];
  var bestFrom = -1, bestTo = -1, bestLen = 0;
  for (var i = 0; i < words.length; i++) {
    for (final p0 in starts[i]) {
      var len = words[i].length;
      var j = i + 1;
      var cursor = p0 + words[i].length;
      while (j < words.length && starts[j].contains(cursor)) {
        cursor += words[j].length;
        len += words[j].length;
        j++;
      }
      if (len > bestLen) {
        bestLen = len;
        bestFrom = p0;
        bestTo = cursor;
      }
    }
  }
  // Порог: короче трети фрагмента или ~10 символов — совпадение слишком
  // слабое, закрасить «похожее место» опаснее, чем не закрашивать вовсе.
  final minLen = body.length < 30 ? 10 : body.length ~/ 3;
  if (bestLen < minLen || bestFrom < 0) return const [];
  return [back(bestFrom, bestTo)];
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
