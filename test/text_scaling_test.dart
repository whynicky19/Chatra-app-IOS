import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/screens/settings/settings_shared.dart';

/// Поддержка системного размера шрифта (iOS Dynamic Type / Android font size).
///
/// Раньше приложение вообще не учитывало textScaler, а кнопки имели жёсткий
/// `height: 52` — при увеличенном шрифте подпись обрезалась. Теперь высота
/// минимальная, а в MaterialApp стоит потолок масштаба 1.3.
///
/// Тесты падают на любом RenderFlex overflow, поэтому сам факт успешного
/// прохождения и есть проверка вёрстки.
void main() {
  // MediaQuery обязан быть ВНУТРИ MaterialApp: тот строит собственный
  // MediaQuery.fromView и внешний просто затирает (на этом тест сначала и
  // провалился — масштаб не применялся вовсе).
  Widget wrap(Widget child, double scale) => MaterialApp(
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: inner!,
        ),
        home: Scaffold(
          body: Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          )),
        ),
      );

  testWidgets('кнопка растёт под крупный шрифт вместо обрезки', (tester) async {
    // Узкий экран + длинная подпись — худший случай.
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    // Мерим сам контейнер кнопки: SheetButton — это GestureDetector, его
    // размер берётся с внешнего бокса и роста бы не показал.
    double buttonHeight() => tester.getSize(
        find.descendant(
          of: find.byType(SheetButton),
          matching: find.byType(AnimatedContainer),
        )).height;

    for (final scale in <double>[1.0, 1.3, 2.0, 3.0]) {
      await tester.pumpWidget(wrap(
        SheetButton(
          label: 'Изменить пароль и подтвердить действие',
          color: Colors.blue,
          enabled: true,
          busy: false,
          onTap: () {},
        ),
        scale,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'вёрстка кнопки переполнилась при масштабе $scale');
      // Базовая высота сохраняется, но кнопка не ниже минимума.
      expect(buttonHeight(), greaterThanOrEqualTo(52.0));
    }
  });

  testWidgets('высота кнопки увеличивается вместе с масштабом', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Future<double> measure(double scale) async {
      await tester.pumpWidget(wrap(
        SheetButton(
          label: 'Изменить пароль и подтвердить действие',
          color: Colors.blue,
          enabled: true,
          busy: false,
          onTap: () {},
        ),
        scale,
      ));
      await tester.pumpAndSettle();
      return tester.getSize(
          find.descendant(
            of: find.byType(SheetButton),
            matching: find.byType(AnimatedContainer),
          )).height;
    }

    final small = await measure(1.0);
    final large = await measure(2.5);
    expect(large, greaterThan(small),
        reason: 'при крупном шрифте кнопка обязана расти, а не резать текст');
  });
}
