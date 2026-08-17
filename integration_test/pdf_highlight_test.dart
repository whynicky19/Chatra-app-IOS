// Проверка выделений на настоящем PDF: рендер и текстовый слой считает PDFium,
// поэтому смысл теста именно в прогоне на устройстве/симуляторе, а не в
// unit-окружении.
//
// Запуск:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/pdf_highlight_test.dart -d <simulator>
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:chatra_app/models/annotation.dart';
import 'package:chatra_app/utils/highlight_anchor.dart';
import 'package:chatra_app/utils/pdf_highlight_geometry.dart';

/// Минимальный PDF с двумя страницами текста — собирается прямо здесь, чтобы
/// тест не зависел от файлов на бэкенде.
Uint8List _buildPdf() {
  final objects = <int, String>{};
  String content(List<String> lines) {
    final b = StringBuffer('BT\n/F1 14 Tf\n72 760 Td\n20 TL\n');
    for (final l in lines) {
      b.write('(${l.replaceAll('(', r'\(').replaceAll(')', r'\)')}) Tj T*\n');
    }
    b.write('ET');
    return b.toString();
  }

  final c1 = content([
    'Lecture 5. Encapsulation in object-oriented design',
    '',
    'Encapsulation is the bundling of data with the methods that operate',
    'on that data. It restricts direct access to some components.',
  ]);
  final c2 = content(['Page two. Invariants and information hiding']);

  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[2] = '<< /Type /Pages /Kids [3 0 R 6 0 R] /Count 2 >>';
  objects[3] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R '
      '/Resources << /Font << /F1 5 0 R >> >> >>';
  objects[4] = '<< /Length ${c1.length} >>\nstream\n$c1\nendstream';
  objects[5] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';
  objects[6] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 7 0 R '
      '/Resources << /Font << /F1 5 0 R >> >> >>';
  objects[7] = '<< /Length ${c2.length} >>\nstream\n$c2\nendstream';

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int, int>{};
  for (final n in objects.keys.toList()..sort()) {
    offsets[n] = out.length;
    out.write('$n 0 obj\n${objects[n]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final n in objects.keys.toList()..sort()) {
    out.write('${offsets[n]!.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(out.toString().codeUnits);
}

Annotation _annotation({
  required String text,
  String prefix = '',
  String suffix = '',
  int start = 0,
  int end = 0,
  int page = 1,
}) => Annotation(
      id: 1, lectureId: 1, classId: 1, fileIndex: 0, page: page,
      selectedText: text, prefix: prefix, suffix: suffix,
      startOffset: start, endOffset: end, color: 'yellow',
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PdfDocument doc;
  late PdfPageText page1Text;

  setUpAll(() async {
    pdfrxFlutterInitialize();
    final file = File('${Directory.systemTemp.path}/chatra_pdf_highlight_test.pdf');
    await file.writeAsBytes(_buildPdf());
    doc = await PdfDocument.openFile(file.path);
    page1Text = await doc.pages[0].loadStructuredText();
  });

  tearDownAll(() => doc.dispose());

  testWidgets('PDFium отдаёт текст страницы', (tester) async {
    expect(doc.pages.length, 2);
    expect(page1Text.fullText, contains('Encapsulation'));
    expect(page1Text.charRects.length, page1Text.fullText.length);
  });

  testWidgets('выделение внутри строки закрашивается одной полосой', (tester) async {
    final rects = highlightRects(page1Text, _annotation(text: 'bundling of data'));
    expect(rects.length, 1);
    final r = rects.first;
    // Полоса лежит внутри страницы и не растянута на всю её ширину.
    expect(r.left, greaterThan(0));
    expect(r.right, lessThan(595));
    expect(r.width, greaterThan(50));
    expect(r.height, greaterThan(5));
  });

  testWidgets('выделение через две строки даёт две отдельные полосы', (tester) async {
    final rects = highlightRects(
      page1Text,
      _annotation(text: 'that operate on that data'),
    );
    expect(rects.length, 2, reason: 'по одной полосе на строку, а не один прямоугольник на абзац');
    // Вторая строка ниже первой (в координатах PDF ось Y снизу вверх).
    expect(rects[1].bottom, lessThan(rects[0].bottom));
  });

  testWidgets('пометка с другого клиента (без смещений) находится по якорю', (tester) async {
    // Так её сохранил бы сайт: смещения из pdf.js здесь не совпадают.
    final rects = highlightRects(page1Text, _annotation(
      text: 'restricts direct access',
      prefix: 'It', suffix: 'to some components',
      start: 9999, end: 10022,
    ));
    expect(rects, isNotEmpty);
  });

  testWidgets('чужого текста на странице нет — ничего не подсвечиваем', (tester) async {
    expect(highlightRects(page1Text, _annotation(text: 'полиморфизм и наследование')), isEmpty);
    // И текст второй страницы не находится на первой.
    expect(highlightRects(page1Text, _annotation(text: 'Invariants and information hiding')), isEmpty);
  });

  testWidgets('смещения совпадают с тем, что вернёт выделение в самом просмотрщике', (tester) async {
    // Эмулируем сохранение: берём кусок текста страницы по смещениям, как это
    // делает getSelectedTextRanges(), и проверяем, что якорь и поиск сходятся.
    final start = page1Text.fullText.indexOf('methods');
    final end = start + 'methods'.length;
    final anchor = anchorAround(page1Text.fullText, start, end);
    final rects = highlightRects(page1Text, _annotation(
      text: 'methods', prefix: anchor.prefix, suffix: anchor.suffix, start: start, end: end,
    ));
    expect(rects.length, 1);
  });
}
