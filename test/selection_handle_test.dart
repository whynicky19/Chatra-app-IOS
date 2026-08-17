import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/screens/classes/widgets/selection_handle.dart';

/// Маркер выделения: видимая часть маленькая, зона захвата — большая.
///
/// Регрессия на жалобу «выделил слово и не можешь двигать»: у стандартных
/// маркеров pdfrx (и у первой версии этого виджета) тащить можно было только
/// за саму фигуру, и попасть в неё пальцем не получалось.
Future<void> _pump(WidgetTester tester, {required bool isStart, bool dragging = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: Center(
      child: SelectionHandle(
        isStart: isStart,
        lineHeight: 18,
        color: const Color(0xFF00B1C9),
        dragging: dragging,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('зона захвата с запасом от 44 по HIG', (tester) async {
    await _pump(tester, isStart: true);
    final size = tester.getSize(find.byType(SelectionHandle));
    expect(size, const Size(SelectionHandle.defaultTouchSize, SelectionHandle.defaultTouchSize));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('шарик стоит в центре зоны захвата, а не в углу', (tester) async {
    await _pump(tester, isStart: true);
    final box = tester.getRect(find.byType(SelectionHandle));
    final ball = tester.getRect(find.byType(AnimatedScale));
    // По горизонтали — ровно по центру; по вертикали шарик смещён на ножку,
    // но остаётся внутри центральной трети.
    expect(ball.center.dx, closeTo(box.center.dx, 0.5));
    expect((ball.center.dy - box.center.dy).abs(), lessThan(box.height / 3));
  });

  testWidgets('видимая часть маленькая: шарик 11 и ножка по высоте строки', (tester) async {
    await _pump(tester, isStart: true);
    final sizes = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(SelectionHandle), matching: find.byType(Container)))
        .map((c) => (c.constraints?.maxWidth, c.constraints?.maxHeight))
        .toList();
    expect(sizes, contains((SelectionHandle.ballSize, SelectionHandle.ballSize)));
    expect(sizes, contains((SelectionHandle.stemWidth, 18.0)));
  });

  testWidgets('у начального маркера шарик сверху, у конечного — снизу', (tester) async {
    await _pump(tester, isStart: true);
    final startColumn = tester.widget<Column>(
        find.descendant(of: find.byType(SelectionHandle), matching: find.byType(Column)));
    // Первым в колонке идёт шарик (он же обёрнут в AnimatedScale).
    expect(startColumn.children.first, isA<AnimatedScale>());

    await _pump(tester, isStart: false);
    final endColumn = tester.widget<Column>(
        find.descendant(of: find.byType(SelectionHandle), matching: find.byType(Column)));
    expect(endColumn.children.last, isA<AnimatedScale>());
  });

  testWidgets('при перетаскивании шарик подрастает — отклик на нажатие', (tester) async {
    await _pump(tester, isStart: true, dragging: false);
    final normal = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    await _pump(tester, isStart: true, dragging: true);
    final active = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(active, greaterThan(normal));
  });
}
