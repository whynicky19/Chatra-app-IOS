/// Чистка текста, извлечённого из PDF движком PDFium.
///
/// Символы без Unicode-маппинга (маркеры списков «•» в PDF, сконвертированном
/// из Word, стрелки, спецзнаки шрифтов) приходят как U+FFFD — «знак вопроса в
/// ромбе». Без чистки такие символы попадают в пометки и «Мои выделения».
///
/// Замена строго 1:1 по длине: смещения в тексте страницы используются
/// подсветкой пометок (charRects), и любое изменение длины строки сломало бы
/// геометрию.
String sanitizePdfSymbols(String text) {
  if (!text.contains('\uFFFD')) return text;
  final sb = StringBuffer();
  var lineStart = true;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '\uFFFD') {
      // В начале строки это почти всегда бюллетень списка из Word; в середине —
      // неизвестный спецзнак, для него нейтральное тире честнее «ромба».
      sb.write(lineStart ? '\u2022' : '\u2013');
      continue;
    }
    if (ch == '\n' || ch == '\r') {
      lineStart = true;
      sb.write(ch);
      continue;
    }
    if (ch == ' ' || ch == '\t') {
      sb.write(ch);
      continue;
    }
    lineStart = false;
    sb.write(ch);
  }
  return sb.toString();
}
