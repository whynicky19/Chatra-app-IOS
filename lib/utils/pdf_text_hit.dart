import 'dart:ui';

import 'package:pdfrx/pdfrx.dart';

import 'highlight_anchor.dart';

/// Попадание пальца в текст страницы PDF.
///
/// Просмотрщик умеет вести выделение сам, но только пока палец двигается: он
/// пересчитывает край выделения из события движения. Нам этого мало — выделение
/// должно тянуться и когда палец стоит у края экрана, а страница уезжает под
/// ним (автопрокрутка). Поэтому положение края считаем сами: по координатам
/// точки находим символ под ней.
///
/// Все координаты — документа (страницы разложены в одной системе координат,
/// масштаб живёт в матрице просмотра), поэтому прямоугольники символов
/// считаются один раз на страницу и не зависят от зума.
List<Rect> charRectsInDocument(PdfPageText text, PdfPage page, Rect pageRect) {
  final rects = List<Rect>.filled(text.charRects.length, Rect.zero);
  for (var i = 0; i < text.charRects.length; i++) {
    final r = text.charRects[i];
    // Пробелы и переносы приходят пустыми — цепляться за них не за что.
    if (r.width == 0 && r.height == 0) continue;
    rects[i] = r
        .toRect(page: page, scaledPageSize: pageRect.size)
        .translate(pageRect.left, pageRect.top);
  }
  return rects;
}

/// Индекс символа под точкой [point]; null — если на странице нет текста.
///
/// Точное попадание бывает редко: палец идёт по строке, между строк и по полям.
/// Поэтому промах разрешается ближайшим символом, но строка важнее колонки —
/// иначе палец, проведённый по левому полю, цеплялся бы за концы соседних
/// строк вместо их начал.
int? charIndexAtPoint(List<Rect> rects, Offset point) {
  var best = -1;
  var bestScore = double.infinity;
  for (var i = 0; i < rects.length; i++) {
    final r = rects[i];
    if (r.isEmpty) continue;
    if (r.contains(point)) return i;
    final dy = point.dy < r.top
        ? r.top - point.dy
        : point.dy > r.bottom
            ? point.dy - r.bottom
            : 0.0;
    final dx = point.dx < r.left
        ? r.left - point.dx
        : point.dx > r.right
            ? point.dx - r.right
            : 0.0;
    final score = dy * 4 + dx;
    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best < 0 ? null : best;
}

/// Начало слова, в которое попал символ [index].
///
/// Границы выделения прилипают к словам, как в приложениях Apple: палец
/// останавливается посреди слова, а выделение — нет.
int wordStart(String text, int index) {
  if (text.isEmpty) return 0;
  final i = index.clamp(0, text.length - 1);
  final w = snapToWords(text, i, i + 1);
  return w.end > w.start ? w.start : i;
}

/// Последний символ слова, в которое попал символ [index] (включительно —
/// такие индексы у краёв выделения в pdfrx).
int wordEnd(String text, int index) {
  if (text.isEmpty) return 0;
  final i = index.clamp(0, text.length - 1);
  final w = snapToWords(text, i, i + 1);
  return w.end > w.start ? w.end - 1 : i;
}
