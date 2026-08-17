import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/screens/classes/widgets/quoted_fragment.dart';
import 'package:chatra_app/utils/ai_ask.dart';

/// Вопрос по выделенному фрагменту показывается в чате цитатой из материала:
/// вводная строка, подсвеченный фрагмент и карточка источника.
void main() {
  test('разбирает сообщение, которое сам же и строит buildQuotePrompt', () {
    final text = buildQuotePrompt(
      lang: 'RU',
      text: 'Инкапсуляция — это механизм, объединяющий данные и методы',
      lectureTitle: 'Инкапсуляция',
      page: 12,
    );
    final q = QuotedFragment.tryParse(text);
    expect(q, isNotNull);
    expect(q!.quote, 'Инкапсуляция — это механизм, объединяющий данные и методы');
    expect(q.lectureTitle, 'Инкапсуляция');
    expect(q.page, 12);
    expect(q.intro, contains('Объясни этот фрагмент'));
  });

  test('английская и казахская формулировки тоже разбираются', () {
    final en = QuotedFragment.tryParse(buildQuotePrompt(
      lang: 'EN', text: 'fragment text', lectureTitle: 'Encapsulation', page: 3));
    expect(en?.page, 3);
    expect(en?.lectureTitle, 'Encapsulation');

    final kz = QuotedFragment.tryParse(buildQuotePrompt(
      lang: 'KZ', text: 'үзінді', lectureTitle: 'Инкапсуляция', page: 7));
    expect(kz?.quote, 'үзінді');
    expect(kz?.page, 7);
  });

  test('без страницы (текст лекции) карточка источника показывает только лекцию', () {
    final q = QuotedFragment.tryParse(buildQuotePrompt(
      lang: 'RU', text: 'фрагмент', lectureTitle: 'Матрицы'));
    expect(q, isNotNull);
    expect(q!.page, isNull);
    expect(q.lectureTitle, 'Матрицы');
  });

  test('обычное сообщение не превращается в цитату', () {
    expect(QuotedFragment.tryParse('Привет, объясни лекцию 2'), isNull);
    expect(QuotedFragment.tryParse('Объясни этот фрагмент'), isNull, reason: 'нет самой цитаты');
  });

  testWidgets('в пузыре видны фрагмент и источник', (tester) async {
    final q = QuotedFragment.tryParse(buildQuotePrompt(
      lang: 'RU', text: 'скрывает внутреннее состояние', lectureTitle: 'Инкапсуляция', page: 12))!;

    await tester.pumpWidget(CupertinoApp(
      home: Center(child: QuotedFragmentBubble(
        fragment: q,
        bubbleColor: const Color(0xFF00B1C9),
        pageLabel: 'стр.',
      )),
    ));

    expect(find.text('скрывает внутреннее состояние'), findsOneWidget);
    expect(find.text('Инкапсуляция · стр. 12'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);

    // Фрагмент подсвечен — как пометка в самой лекции.
    final quote = tester.widget<Text>(find.text('скрывает внутреннее состояние'));
    expect(quote.style?.backgroundColor, isNotNull);
  });
}
