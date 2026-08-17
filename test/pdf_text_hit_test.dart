import 'dart:ui';

import 'package:chatra_app/utils/pdf_text_hit.dart';
import 'package:flutter_test/flutter_test.dart';

/// Две строки по пять символов: строка на y 0..10, следующая на y 20..30.
List<Rect> _line(double top, int count, {double x0 = 0}) => List.generate(
    count, (i) => Rect.fromLTWH(x0 + i * 10, top, 10, 10));

void main() {
  group('символ под пальцем', () {
    final rects = [..._line(0, 5), ..._line(20, 5)];

    test('точное попадание внутрь символа', () {
      expect(charIndexAtPoint(rects, const Offset(25, 5)), 2);
      expect(charIndexAtPoint(rects, const Offset(45, 25)), 9);
    });

    test('палец за концом строки цепляет последний символ этой строки', () {
      expect(charIndexAtPoint(rects, const Offset(300, 5)), 4);
    });

    test('палец на левом поле цепляет начало ближайшей строки, а не конец соседней', () {
      // Ровно та ошибка, из-за которой выделение прыгало на строку выше:
      // по прямому расстоянию ближе конец предыдущей строки.
      expect(charIndexAtPoint(rects, const Offset(-40, 25)), 5);
    });

    test('палец между строк выбирает ближайшую', () {
      expect(charIndexAtPoint(rects, const Offset(5, 12)), 0);
      expect(charIndexAtPoint(rects, const Offset(5, 18)), 5);
    });

    test('пустые прямоугольники (пробелы, переносы) пропускаются', () {
      final withGap = [Rect.zero, ..._line(0, 2, x0: 10)];
      expect(charIndexAtPoint(withGap, const Offset(0, 5)), 1);
    });

    test('страница без текста — не за что цепляться', () {
      expect(charIndexAtPoint(const [], const Offset(10, 10)), isNull);
      expect(charIndexAtPoint([Rect.zero], const Offset(10, 10)), isNull);
    });
  });

  group('прилипание к словам', () {
    const text = 'Инкапсуляция скрывает состояние';

    test('палец посреди слова — граница уезжает на его край', () {
      expect(wordStart(text, 5), 0);
      expect(wordEnd(text, 5), 'Инкапсуляция'.length - 1);
      expect(wordStart(text, 16), 13);
      expect(wordEnd(text, 16), 'Инкапсуляция скрывает'.length - 1);
    });

    test('край слова остаётся на месте', () {
      expect(wordStart(text, 0), 0);
      expect(wordEnd(text, text.length - 1), text.length - 1);
    });

    test('на пробеле границу не двигаем', () {
      expect(wordStart(text, 12), 12);
      expect(wordEnd(text, 12), 12);
    });

    test('индекс за пределами текста не ломает границу', () {
      expect(wordStart(text, 999), lessThan(text.length));
      // Индекс до начала текста прижимается к первому слову, а не улетает.
      expect(wordEnd(text, -5), 'Инкапсуляция'.length - 1);
      expect(wordStart('', 3), 0);
    });
  });
}
