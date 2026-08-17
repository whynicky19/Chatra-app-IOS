import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chatra_app/providers/l10n_provider.dart';
import 'package:chatra_app/screens/onboarding/onboarding_screen.dart';

/// Интро должно показываться ровно один раз и всегда иметь выход.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(VoidCallback onDone) => ChangeNotifierProvider(
        create: (_) => L10n(),
        child: MaterialApp(home: OnboardingScreen(onDone: onDone)),
      );

  test('isSeen ложь до показа и истина после markSeen', () async {
    expect(await OnboardingScreen.isSeen(), isFalse);
    await OnboardingScreen.markSeen();
    expect(await OnboardingScreen.isSeen(), isTrue);
  });

  testWidgets('«Пропустить» закрывает интро и помечает его показанным',
      (tester) async {
    var done = false;
    await tester.pumpWidget(wrap(() => done = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Пропустить'));
    await tester.pumpAndSettle();

    expect(done, isTrue, reason: 'onDone обязан вызваться');
    expect(await OnboardingScreen.isSeen(), isTrue,
        reason: 'после пропуска интро больше не показывается');
  });

  testWidgets('кнопка листает страницы, на последней — «Начать»',
      (tester) async {
    var done = false;
    await tester.pumpWidget(wrap(() => done = true));
    await tester.pumpAndSettle();

    // Страница 1 — «Далее».
    expect(find.text('Далее'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    // Страницы 2 и 3 (выделения в лекции, ИИ знает курс) — тоже «Далее».
    for (var i = 0; i < 2; i++) {
      expect(find.text('Далее'), findsOneWidget);
      expect(find.text('Начать'), findsNothing);
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
    }

    // Страница 4 (проверка ИИ) — последняя.
    expect(find.text('Начать'), findsOneWidget);
    expect(done, isFalse, reason: 'до нажатия «Начать» интро не закрывается');

    await tester.tap(find.text('Начать'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(await OnboardingScreen.isSeen(), isTrue);
  });

  testWidgets('страница про выделения показывает цвета и действия',
      (tester) async {
    await tester.pumpWidget(wrap(() {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();

    expect(find.text('Выделяйте прямо в лекции'), findsOneWidget);
    // На мокапе — та же панель, что и в просмотрщике: цвета и два действия.
    expect(find.text('Заметка'), findsOneWidget);
    expect(find.text('Спросить AI'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.sparkles), findsOneWidget);
  });

  testWidgets('вёрстка интро переживает крупный системный шрифт',
      (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => L10n(),
      child: MaterialApp(
        builder: (c, inner) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: inner!,
        ),
        home: OnboardingScreen(onDone: () {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
