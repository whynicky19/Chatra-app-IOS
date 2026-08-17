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

  test('фрагмента нет в тексте — ничего не подсвечиваем', () {
    expect(locateAnnotation(_text, _a(text: 'полиморфизм', start: 0, end: 11)), isNull);
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
