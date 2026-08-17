import 'package:pdfrx/pdfrx.dart';

import '../models/annotation.dart';
import 'highlight_anchor.dart';

/// Геометрия пометки на странице PDF: где закрасить фрагмент.
///
/// Возвращает по одной полосе на строку текста — выделение через несколько
/// строк должно лечь несколькими прямоугольниками, а не одним на весь абзац
/// (иначе закрашиваются поля и соседние строки).
///
/// Координаты — страницы PDF; в координаты экрана их переводит
/// PdfRect.toRect(page:, scaledPageSize:) уже при отрисовке, поэтому масштаб и
/// размер экрана на результат не влияют.
List<PdfRect> highlightRects(PdfPageText text, Annotation a) {
  final m = locateAnnotation(text.fullText, a);
  if (m == null) return const [];

  final out = <PdfRect>[];
  PdfRect? line;
  for (var i = m.start; i < m.end && i < text.charRects.length; i++) {
    final r = text.charRects[i];
    if (r.width == 0 && r.height == 0) continue; // пробел/перенос
    if (line == null) {
      line = r;
    } else if ((r.bottom - line.bottom).abs() <= line.height * 0.6) {
      line = line.merge(r);
    } else {
      // Символ ушёл на другую строку — предыдущую полосу закрываем.
      out.add(line);
      line = r;
    }
  }
  if (line != null) out.add(line);
  return out;
}
