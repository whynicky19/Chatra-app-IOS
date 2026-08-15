// Визуальный прогон двух перерисованных экранов: календарь дедлайнов и
// уведомления. Тест ничего не утверждает — он логинится, открывает экраны и
// держит каждый на виду, чтобы снаружи можно было снять скриншоты через
// `xcrun simctl io <udid> screenshot` (см. chatra-integration-smoke).
//
// Запуск:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/redesign_visual_test.dart -d <simulator>
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chatra_app/main.dart' as app;

const _qaEmail = 'qa_tester_2026@example.com';
const _qaPassword = 'QaTest12345';

void _drain(WidgetTester tester) {
  for (var e = tester.takeException(); e != null; e = tester.takeException()) {
    // ignore: avoid_print
    print('APP EXCEPTION: $e');
  }
}

Future<void> _waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 25), String? reason}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    _drain(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Не дождался ${reason ?? finder.toString()} за $timeout');
}

/// pumpAndSettle не годится: в приложении есть бесконечные анимации.
Future<void> _hold(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    _drain(tester);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('визуал: календарь дедлайнов и уведомления', (tester) async {
    app.main();

    await _waitFor(
      tester,
      find.textContaining('Настройки')
          .or(find.text('Добро пожаловать'))
          .or(find.text('Университет')),
      timeout: const Duration(seconds: 40),
      reason: 'стартовый экран',
    );

    if (find.text('Университет').evaluate().isNotEmpty) {
      await tester.tap(find.text('Университет'));
      await _hold(tester, const Duration(milliseconds: 800));
      await _waitFor(tester, find.text('Добро пожаловать'), reason: 'экран входа');
    }

    if (find.text('Добро пожаловать').evaluate().isNotEmpty) {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), _qaEmail);
      await tester.enterText(fields.at(1), _qaPassword);
      await tester.tap(find.text('Войти'));
      await _waitFor(tester, find.text('Настройки'),
          timeout: const Duration(seconds: 30), reason: 'главный экран');
    }

    await _waitFor(tester, find.text('Предметы'), reason: 'вкладка Предметы');
    await _hold(tester, const Duration(seconds: 4));

    // ── Календарь дедлайнов ─────────────────────────────────────────────
    // ignore: avoid_print
    print('>>> SHOT: calendar');
    await tester.tap(find.byIcon(CupertinoIcons.calendar).first, warnIfMissed: false);
    await _waitFor(tester, find.text('Дедлайны'), reason: 'экран календаря');
    await _hold(tester, const Duration(seconds: 12));

    // Листаем месяц свайпом — проверяем, что PageView живой.
    // ignore: avoid_print
    print('>>> SHOT: calendar next month');
    await tester.drag(find.byType(PageView).first, const Offset(-300, 0));
    await _hold(tester, const Duration(seconds: 8));

    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await _waitFor(tester, find.text('Предметы'), reason: 'возврат на главную');
    await _hold(tester, const Duration(seconds: 2));

    // ── Уведомления ─────────────────────────────────────────────────────
    // ignore: avoid_print
    print('>>> SHOT: notifications');
    await tester.tap(find.byIcon(CupertinoIcons.bell).first, warnIfMissed: false);
    await _waitFor(tester, find.text('Уведомления'), reason: 'экран уведомлений');
    await _hold(tester, const Duration(seconds: 14));

    _drain(tester);
    // ignore: avoid_print
    print('>>> SHOT: done');
  });
}

extension _Or on Finder {
  Finder or(Finder other) => _OrFinder(this, other);
}

class _OrFinder extends Finder {
  _OrFinder(this.a, this.b);
  final Finder a;
  final Finder b;

  @override
  // ignore: deprecated_member_use
  String get description => 'either of two finders';

  @override
  Iterable<Element> findInCandidates(Iterable<Element> candidates) sync* {
    // ignore: deprecated_member_use
    yield* a.apply(candidates);
    // ignore: deprecated_member_use
    yield* b.apply(candidates);
  }
}
