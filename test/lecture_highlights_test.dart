import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chatra_app/models/annotation.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/classes/lecture_detail_screen.dart';
import 'package:chatra_app/services/api_service.dart';
import 'package:chatra_app/theme/app_theme.dart';
import 'package:chatra_app/utils/ai_ask.dart';

/// Выделения в тексте лекции: приходят с сервера, рисуются поверх текста,
/// правятся и уводят вопрос в ИИ-чат класса вместе со ссылкой на источник.
const _content = 'Инкапсуляция скрывает внутреннее состояние объекта. '
    'Наружу класс отдаёт только интерфейс, а не представление данных.';

class _FakeApi extends ApiService {
  _FakeApi({this.rows = const []}) : super(baseUrl: 'http://localhost:1/api');

  List<dynamic> rows;
  Map<String, dynamic>? created;
  Map<String, dynamic>? patched;
  int? deleted;

  @override
  Future<List<dynamic>> getAnnotations({int? lectureId, int? classId}) async => rows;

  @override
  Future<Map<String, dynamic>> createAnnotation({
    required int lectureId,
    required int classId,
    required String selectedText,
    required int startOffset,
    required int endOffset,
    String prefix = '',
    String suffix = '',
    int fileIndex = -1,
    int page = 0,
    String color = 'yellow',
    String? comment,
  }) async {
    created = {
      'id': 501, 'lecture_id': lectureId, 'class_id': classId, 'file_index': fileIndex,
      'page': page, 'selected_text': selectedText, 'prefix': prefix, 'suffix': suffix,
      'start_offset': startOffset, 'end_offset': endOffset, 'color': color, 'comment': comment,
      'lecture_title': 'Инкапсуляция', 'updated_at': '2026-08-17T10:00:00',
    };
    return created!;
  }

  @override
  Future<Map<String, dynamic>> updateAnnotation(int id, {String? color, String? comment}) async {
    patched = {'id': id, 'color': color, 'comment': comment};
    final row = Map<String, dynamic>.from(rows.first as Map);
    if (color != null) row['color'] = color;
    if (comment != null) row['comment'] = comment;
    return row;
  }

  @override
  Future<void> deleteAnnotation(int id) async => deleted = id;
}

Map<String, dynamic> _row({
  int id = 1,
  int start = 0,
  int end = 12,
  String color = 'yellow',
  String? comment,
  int fileIndex = -1,
  int page = 0,
  String? text,
}) => {
      'id': id, 'lecture_id': 32, 'class_id': 27, 'file_index': fileIndex, 'page': page,
      'selected_text': text ?? _content.substring(start, end),
      'prefix': '', 'suffix': '', 'start_offset': start, 'end_offset': end,
      'color': color, 'comment': comment, 'lecture_title': 'Инкапсуляция',
      'updated_at': '2026-08-17T10:00:00',
    };

Future<void> _pump(WidgetTester tester, _FakeApi api, {bool withIds = true}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => L10n()),
      Provider<ApiService>.value(value: api),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: LectureDetailScreen(
        title: 'Инкапсуляция',
        dateLabel: '5 июл. 2026 г.',
        content: _content,
        files: const [],
        onOpenFile: (_, __, ___) {},
        lectureId: withIds ? 32 : null,
        classId: withIds ? 27 : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Стили всех кусочков текста лекции — по ним видно, что именно подсвечено.
List<TextSpan> _bodySpans(WidgetTester tester) {
  final rich = tester.widgetList<Text>(find.byType(Text))
      .firstWhere((t) => t.textSpan != null && (t.textSpan as TextSpan).children != null);
  return ((rich.textSpan as TextSpan).children ?? []).cast<TextSpan>();
}

void main() {
  testWidgets('выделения с сервера рисуются поверх текста лекции', (tester) async {
    final api = _FakeApi(rows: [_row(start: 0, end: 12, color: 'green')]);
    await _pump(tester, api);

    final spans = _bodySpans(tester);
    final marked = spans.where((s) => s.style?.backgroundColor != null).toList();
    expect(marked.length, 1);
    expect(marked.first.text, 'Инкапсуляция');
    expect(marked.first.style!.backgroundColor!.a, greaterThan(0));
    // Остальной текст остался без заливки и не потерялся.
    expect(spans.map((s) => s.text).join(), _content);
  });

  testWidgets('заметка помечает фрагмент подчёркиванием', (tester) async {
    final api = _FakeApi(rows: [_row(start: 0, end: 12, comment: 'спросить на семинаре')]);
    await _pump(tester, api);

    final marked = _bodySpans(tester).firstWhere((s) => s.style?.backgroundColor != null);
    expect(marked.style!.decoration, TextDecoration.underline);
  });

  testWidgets('пересекающиеся выделения не задваивают текст', (tester) async {
    final api = _FakeApi(rows: [
      _row(id: 1, start: 0, end: 20),
      _row(id: 2, start: 10, end: 30, color: 'blue'),
    ]);
    await _pump(tester, api);
    expect(_bodySpans(tester).map((s) => s.text).join(), _content);
  });

  testWidgets('«Мои выделения» показывает и пометки из PDF, сделанные на сайте', (tester) async {
    final api = _FakeApi(rows: [
      _row(id: 7, fileIndex: 0, page: 12, text: 'фрагмент из файла лекции'),
    ]);
    await _pump(tester, api);

    expect(find.text('МОИ ВЫДЕЛЕНИЯ'), findsOneWidget);
    expect(find.text('фрагмент из файла лекции'), findsOneWidget);
    // Источник виден: лекция и страница.
    expect(find.textContaining('стр. 12'), findsOneWidget);
    // В самом тексте лекции такая пометка не рисуется — её места здесь нет.
    expect(_bodySpans(tester).where((s) => s.style?.backgroundColor != null), isEmpty);
  });

  testWidgets('тап по пометке в тексте открывает действия, «Спросить AI» уводит вопрос в чат класса',
      (tester) async {
    final api = _FakeApi(rows: [_row(start: 0, end: 12, text: 'сохранённый фрагмент')]);
    Object? popped;
    // Экран открывается push'ем, а результат забирается из его Future — ровно
    // так, как это делает class_detail_screen.
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => L10n()),
        Provider<ApiService>.value(value: api),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(builder: (ctx) => CupertinoButton(
          onPressed: () async {
            popped = await Navigator.push<Object?>(ctx, MaterialPageRoute(
              builder: (_) => LectureDetailScreen(
                title: 'Инкапсуляция',
                dateLabel: '5 июл.',
                content: _content,
                files: const [],
                onOpenFile: (_, __, ___) {},
                lectureId: 32,
                classId: 27,
              ),
            ));
          },
          child: const Text('open'),
        )),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Тап по самой пометке в тексте: TapGestureRecognizer навешен на её span.
    final marked = _bodySpans(tester).firstWhere((s) => s.style?.backgroundColor != null);
    (marked.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();
    expect(find.text('Спросить AI'), findsOneWidget);

    await tester.tap(find.text('Спросить AI'));
    await tester.pumpAndSettle();

    expect(popped, isA<AiAsk>());
    final ask = popped as AiAsk;
    expect(ask.lectureId, 32);
    expect(ask.annotationId, 1);
    // Текст фрагмента в запрос отдельно не кладём — сервер возьмёт его из
    // самой аннотации по annotation_id.
    expect(ask.quote, isNull);
    // Формулировка человеческая, а идентификаторы едут отдельными полями.
    expect(ask.text, contains('Объясни этот фрагмент из лекции «Инкапсуляция»'));
    expect(ask.text, contains('сохранённый фрагмент'));
  });

  testWidgets('строка списка для пометки из PDF открывает те же действия', (tester) async {
    final api = _FakeApi(rows: [
      _row(id: 9, fileIndex: 0, page: 12, text: 'фрагмент со страницы 12'),
    ]);
    await _pump(tester, api);

    final row = find.text('фрагмент со страницы 12');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('Спросить AI'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
  });

  testWidgets('без id лекции выделения выключены и экран работает как раньше', (tester) async {
    final api = _FakeApi(rows: [_row()]);
    await _pump(tester, api, withIds: false);

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('МОИ ВЫДЕЛЕНИЯ'), findsNothing);
    expect(find.textContaining('Инкапсуляция скрывает'), findsOneWidget);
  });

  test('палитра выделений совпадает с сайтом', () {
    expect(highlightColors, ['yellow', 'green', 'blue', 'red']);
    expect(highlightSwatch('yellow'), const Color(0xFFFFD84D));
    // На тёмной теме заливка гасится, иначе текст под ней не читается.
    final light = highlightFill('yellow', Brightness.light).a;
    final dark = highlightFill('yellow', Brightness.dark).a;
    expect(dark, lessThan(light));
  });

  test('вопрос по фрагменту формулируется на языке интерфейса', () {
    expect(
      buildQuotePrompt(lang: 'RU', text: 'фрагмент', lectureTitle: 'Инкапсуляция', page: 12),
      contains('Объясни этот фрагмент из лекции «Инкапсуляция», стр. 12:'),
    );
    expect(
      buildQuotePrompt(lang: 'EN', text: 'fragment', lectureTitle: 'Encapsulation', page: 3),
      contains('Explain this excerpt from the lecture “Encapsulation”, p. 3:'),
    );
    // Без страницы (текст лекции) — без «стр.».
    expect(
      buildQuotePrompt(lang: 'RU', text: 'фрагмент', lectureTitle: 'Инкапсуляция'),
      isNot(contains('стр.')),
    );
  });
}
