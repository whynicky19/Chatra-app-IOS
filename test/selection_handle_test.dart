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

/// Ножка маркера — первый Container в дереве (шарик лежит внутри AnimatedScale).
final _stem = find
    .descendant(of: find.byType(SelectionHandle), matching: find.byType(Container))
    .first;

void main() {
  testWidgets('зона захвата с запасом от 44 по HIG', (tester) async {
    await _pump(tester, isStart: true);
    final size = tester.getSize(find.byType(SelectionHandle));
    expect(size, const Size(SelectionHandle.defaultTouchSize, SelectionHandle.defaultTouchSize));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  testWidgets('запас зоны захвата уходит наружу выделения', (tester) async {
    // У начального маркера палец тянется к нему сверху-слева, у конечного —
    // снизу-справа: туда и уходит бо́льшая часть зоны.
    await _pump(tester, isStart: true);
    var box = tester.getRect(find.byType(SelectionHandle));
    var ball = tester.getRect(find.byType(AnimatedScale));
    expect(ball.center.dx - box.left, greaterThan(box.right - ball.center.dx));
    expect(ball.center.dy - box.top, greaterThan(box.bottom - ball.center.dy));

    await _pump(tester, isStart: false);
    box = tester.getRect(find.byType(SelectionHandle));
    ball = tester.getRect(find.byType(AnimatedScale));
    expect(box.right - ball.center.dx, greaterThan(ball.center.dx - box.left));
    expect(box.bottom - ball.center.dy, greaterThan(ball.center.dy - box.top));
  });

  testWidgets('шарик не выходит за зону захвата', (tester) async {
    for (final isStart in [true, false]) {
      await _pump(tester, isStart: isStart);
      final box = tester.getRect(find.byType(SelectionHandle));
      final ball = tester.getRect(find.byType(AnimatedScale));
      expect(box.contains(ball.center), isTrue);
    }
  });

  testWidgets('видимая часть маленькая: шарик 11 и ножка по высоте строки', (tester) async {
    await _pump(tester, isStart: true);
    final ball = tester.getSize(find.byType(AnimatedScale));
    expect(ball,
        const Size(SelectionHandle.ballSize, SelectionHandle.ballSize));
    expect(tester.getSize(_stem), const Size(SelectionHandle.stemWidth, 18));
  });

  testWidgets('у начального маркера шарик над строкой, у конечного — под ней',
      (tester) async {
    // Ножка идёт вдоль строки, шарик — с внешней стороны: так же, как в iOS.
    await _pump(tester, isStart: true);
    var ball = tester.getRect(find.byType(AnimatedScale));
    var stem = tester.getRect(_stem);
    expect(ball.center.dy, lessThan(stem.center.dy));

    await _pump(tester, isStart: false);
    ball = tester.getRect(find.byType(AnimatedScale));
    stem = tester.getRect(_stem);
    expect(ball.center.dy, greaterThan(stem.center.dy));
  });

  testWidgets('при перетаскивании шарик подрастает — отклик на нажатие', (tester) async {
    await _pump(tester, isStart: true, dragging: false);
    final normal = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    await _pump(tester, isStart: true, dragging: true);
    final active = tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(active, greaterThan(normal));
  });
}
