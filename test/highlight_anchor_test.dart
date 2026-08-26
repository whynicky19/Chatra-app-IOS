import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/models/annotation.dart';
import 'package:chatra_app/utils/highlight_anchor.dart';

/// Поиск сохранённого выделения в тексте, который сейчас на экране.
///
/// Главный сценарий здесь — «пометку сделали на другом устройстве»: PDF на
/// сайте разбирает pdf.js, в приложении — PDFium, и потоки текста у них
/// расходятся в пробелах и переносах, поэтому одних смещений мало.
const _text =
    'Инкапсуляция скрывает внутреннее состояние объекта. '
    'Наружу класс отдаёт только интерфейс. '
    'Инкапсуляция скрывает внутреннее состояние объекта в конце текста.';

Annotation _a({
  required String text,
  int start = 0,
  int end = 0,
  String prefix = '',
  String suffix = '',
}) => Annotation(
      id: 1, lectureId: 1, classId: 1, fileIndex: -1, page: 0,
      selectedText: text, prefix: prefix, suffix: suffix,
      startOffset: start, endOffset: end, color: 'yellow',
    );

void main() {
  test('по смещениям, когда текст на месте', () {
    final m = locateAnnotation(_text, _a(text: 'Инкапсуляция', start: 0, end: 12));
    expect(m, isNotNull);
    expect(_text.substring(m!.start, m.end), 'Инкапсуляция');
  });

  test('смещения с другого клиента: текст найден по якорю, а не по позиции', () {
    // Смещения указывают в середину другого предложения — но prefix/suffix
    // однозначно задают нужное вхождение.
    final m = locateAnnotation(_text, _a(
      text: 'интерфейс',
      start: 3, end: 12,
      prefix: 'отдаёт только ', suffix: '.',
    ));
    expect(m, isNotNull);
    expect(_text.substring(m!.start, m.end), 'интерфейс');
  });

  test('одинаковые фразы: якорь выбирает нужное вхождение', () {
    final first = locateAnnotation(_text, _a(
      text: 'Инкапсуляция скрывает',
      prefix: '', suffix: 'внутреннее состояние объекта. Наружу',
    ));
    final second = locateAnnotation(_text, _a(
      text: 'Инкапсуляция скрывает',
      prefix: 'интерфейс. ', suffix: '',
    ));
    expect(first!.start, 0);
    expect(second!.start, greaterThan(50));
  });

  test('без якоря берётся вхождение, ближайшее к сохранённому смещению', () {
    final near = locateAnnotation(_text, _a(text: 'Инкапсуляция скрывает', start: 90, end: 111));
    expect(near!.start, greaterThan(50));
  });

  test('разница в пробелах и переносах не мешает', () {
    // pdf.js склеивает строки переводом строки, PDFium — пробелом.
    const pdfiumText = 'Encapsulation is the bundling of data with the methods that operate on that data.';
    final m = locateAnnotation(pdfiumText, _a(
      text: 'bundling of data\nwith the methods',
      start: 999, end: 1030,
      prefix: 'is the', suffix: 'that operate',
    ));
    expect(m, isNotNull);
    expect(pdfiumText.substring(m!.start, m.end), 'bundling of data with the methods');
  });

  test('склеенный якорь с сайта тоже находит своё вхождение', () {
    // На сайте соседние строки/ячейки лежат в отдельных узлах DOM, и старые
    // пометки сохранились с якорем без пробелов между ними («Алёна45/100»).
    // В приложении тот же текст приходит от PDFium с пробелами — совпасть
    // должно всё равно, иначе пометки с сайта встают не на то вхождение.
    const pdfium = 'Плясунова Алёна 45/100 Помазков Даниил 55/100 '
        'Семыкина Вероника 65/100 Шкляев Кирилл 85/100';
    final m = locateAnnotation(pdfium, _a(
      text: 'Семыкина Вероника',
      start: 142, end: 159,
      prefix: 'Алёна45/100Помазков Даниил55/100',
      suffix: '65/100Шкляев Кирилл85/100',
    ));
    expect(m, isNotNull);
    expect(pdfium.substring(m!.start, m.end), 'Семыкина Вероника');
  });

  test('фрагмента нет в тексте — ничего не подсвечиваем', () {
    expect(locateAnnotation(_text, _a(text: 'полиморфизм', start: 0, end: 11)), isNull);
  });

  test('слайд: порядок текста перемешан — рисуется цепочка слов', () {
    // Слайд .ppt — абсолютно позиционированные текст-боксы: pdf.js на сайте
    // отдаёт их в порядке потока конверсии, PDFium выстраивает по своим
    // layout-эвристикам. Фраза целиком не находится, но цепочка слов — да:
    // пометка должна хотя бы частично отрисоваться, а не пропасть.
    const pdfium = 'Тема Введение Квантовая механика изучает поведение Итоги курса';
    final m = locateAnnotation(pdfium, _a(
      text: 'Квантовая механика изучает поведение',
      start: 999, end: 1020,
      prefix: 'Введение ', suffix: ' Итоги',
    ));
    // «Квантовая» уехала в другой бокс — рисуем непрерывный остаток.
    const pdfium2 = 'Введение Квантовая Заголовок механика изучает поведение Итоги';
    final m2 = locateAnnotation(pdfium2, _a(
      text: 'Квантовая механика изучает поведение',
      start: 999, end: 1020,
      prefix: '', suffix: '',
    ));
    expect(m2, isNotNull);
    expect(pdfium2.substring(m2!.start, m2.end), 'механика изучает поведение');
  });

  test('типографика (тире) не мешает совпадению', () {
    // Сайт сохраняет то, что дал pdf.js (часто дефис), PDFium отдаёт
    // типографское тире из LibreOffice-конверсии.
    const pdfium = 'Скорость \u2014 векторная величина движения';
    final m = locateAnnotation(pdfium, _a(
      text: 'Скорость - векторная величина',
      start: 0, end: 29,
    ));
    expect(m, isNotNull);
    expect(pdfium.substring(m!.start, m.end), 'Скорость \u2014 векторная величина');
  });

  test('якорь берётся из текста вокруг фрагмента', () {
    final anchor = anchorAround(_text, 13, 21, chars: 12);
    expect(anchor.prefix.length, 12);
    expect(anchor.prefix, endsWith('капсуляция '));
    expect(_text.substring(13, 21), 'скрывает');
    expect(anchor.suffix.startsWith(' внутреннее'), isTrue);
  });

  test('якорь у самого начала и конца текста не выходит за границы', () {
    final start = anchorAround(_text, 0, 12);
    expect(start.prefix, isEmpty);
    final end = anchorAround(_text, _text.length - 6, _text.length);
    expect(end.suffix, isEmpty);
  });
}
