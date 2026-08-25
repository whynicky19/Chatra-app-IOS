import 'package:chatra_app/models/annotation.dart';
import 'package:chatra_app/utils/highlight_anchor.dart';
import 'package:chatra_app/utils/pdf_text_sanitize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('бюллетень в начале строки заменяется на точку', () {
    expect(sanitizePdfSymbols('\uFFFD Insert a function'), '• Insert a function');
    expect(sanitizePdfSymbols('text\n\uFFFD second'), 'text\n• second');
  });

  test('бюллетень после пробелов от края строки — тоже точка', () {
    expect(sanitizePdfSymbols('\n  \uFFFD item'), '\n  • item');
  });

  test('U+FFFD в середине строки становится тире', () {
    expect(sanitizePdfSymbols('a\uFFFDb'), 'a–b');
  });

  test('длина строки сохраняется (важно для смещений пометок)', () {
    const src = 'x\n\uFFFD list of items with \uFFFD inside';
    expect(sanitizePdfSymbols(src).length, src.length);
  });

  test('строка без U+FFFD не меняется', () {
    expect(sanitizePdfSymbols('plain text? yes'), 'plain text? yes');
  });

  test('locateAnnotation сводит пометку с U+FFFD и чистым текстом', () {
    const rawPageText = 'intro\n\uFFFD Insert a function from the list\noutro';
    const savedWithBullet = Annotation(
      id: 1,
      lectureId: 1,
      classId: 1,
      fileIndex: -1,
      page: 1,
      selectedText: '• Insert a function',
      prefix: 'intro',
      suffix: 'from the list',
      startOffset: 0,
      endOffset: 0,
      color: 'yellow',
    );
    final m = locateAnnotation(rawPageText, savedWithBullet);
    expect(m, isNotNull);
    expect(rawPageText.substring(m!.start, m.end).contains('Insert a function'),
        isTrue);

    const savedWithFffd = Annotation(
      id: 2,
      lectureId: 1,
      classId: 1,
      fileIndex: -1,
      page: 1,
      selectedText: '\uFFFD Insert a function',
      prefix: 'intro',
      suffix: 'from the list',
      startOffset: 0,
      endOffset: 0,
      color: 'yellow',
    );
    expect(
      locateAnnotation('intro\n• Insert a function from the list\noutro',
          savedWithFffd),
      isNotNull,
    );
  });
}
