import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/ai/widgets/ai_message_content.dart';

/// Регрессия на моноширинный шрифт кода в ответах ИИ.
///
/// `fontFamily: 'monospace'` — алиас Android/Linux: на iOS/macOS он не
/// резолвится, и код рисовался пропорциональным системным шрифтом (отступы и
/// ASCII-таблицы внутри блока разъезжались). Проверяем, что у стиля кода есть
/// список фолбэков с моно-шрифтами Apple.
void main() {
  Widget wrap(String text) => ChangeNotifierProvider(
        create: (_) => L10n(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiMessageContent(text: text, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      );

  test('фолбэк перечисляет моно-шрифты, которые есть в системе Apple', () {
    expect(kCodeFontFamily, 'monospace');
    expect(kCodeFontFallback, contains('Menlo'));
  });

  testWidgets('код-блок рисуется моноширинным шрифтом', (tester) async {
    const code = 'void main() {\n  print("hi");\n}';
    await tester.pumpWidget(wrap('```dart\n$code\n```'));
    await tester.pump();

    final style = tester.widget<Text>(find.text(code)).style!;
    expect(style.fontFamily, kCodeFontFamily);
    expect(style.fontFamilyFallback, kCodeFontFallback);
  });

  testWidgets('инлайн-код рисуется моноширинным шрифтом', (tester) async {
    await tester.pumpWidget(wrap('Вызови `flutter test` перед пушем'));
    await tester.pump();

    final style = tester.widget<Text>(find.text('flutter test')).style!;
    expect(style.fontFamily, kCodeFontFamily);
    expect(style.fontFamilyFallback, kCodeFontFallback);
  });
}
