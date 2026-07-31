// Смоук-прогон живого приложения на симуляторе против локального бэкенда:
// логин (если сессии нет), все вкладки, экран ИИ, настройки и «AI лимит».
//
// Запуск:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/smoke_test.dart -d <simulator>
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chatra_app/main.dart' as app;

const _qaEmail = 'qa_tester_2026@example.com';
const _qaPassword = 'QaTest12345';

/// Исключения приложения (битые сетевые картинки и т.п.) не должны валить
/// смоук — копим их и печатаем в конце, это и есть результат тестирования.
final List<String> appExceptions = [];

void _drain(WidgetTester tester) {
  for (var e = tester.takeException(); e != null; e = tester.takeException()) {
    appExceptions.add(e.toString());
  }
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    _drain(tester);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Не дождался ${reason ?? finder.toString()} за $timeout');
}

Future<void> _settle(WidgetTester tester,
    [Duration d = const Duration(milliseconds: 600)]) async {
  // pumpAndSettle не годится: в приложении есть бесконечные анимации.
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    _drain(tester);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('смоук: логин → вкладки → ИИ → настройки → AI лимит',
      (tester) async {
    app.main();

    // Стартуем либо в шелл (живая сессия), либо на экран входа/выбора орг-и.
    await _waitFor(
      tester,
      find.textContaining('Настройки')
          .or(find.text('Добро пожаловать'))
          .or(find.text('Университет')),
      timeout: const Duration(seconds: 30),
      reason: 'стартовый экран',
    );

    if (find.text('Университет').evaluate().isNotEmpty) {
      await tester.tap(find.text('Университет'));
      await _settle(tester);
      await _waitFor(tester, find.text('Добро пожаловать'),
          reason: 'экран входа после выбора организации');
    }

    if (find.text('Добро пожаловать').evaluate().isNotEmpty) {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), _qaEmail);
      await tester.enterText(fields.at(1), _qaPassword);
      await tester.tap(find.text('Войти'));
      await _waitFor(tester, find.text('Настройки'),
          timeout: const Duration(seconds: 25), reason: 'главный экран');
    }

    // ── Главная (Предметы) ──────────────────────────────────────────────
    await _waitFor(tester, find.text('Предметы'), reason: 'вкладка Предметы');
    await _settle(tester, const Duration(seconds: 4));

    // ── Вкладка ИИ ──────────────────────────────────────────────────────
    await tester.tap(find.text('ИИ').last, warnIfMissed: false);
    await _waitFor(tester, find.text('Chatra AI'), reason: 'экран ИИ');
    await _settle(tester, const Duration(seconds: 4)); // история + квота

    // ── Вкладка Чаты ────────────────────────────────────────────────────
    await tester.tap(find.text('Чаты').last, warnIfMissed: false);
    await _settle(tester, const Duration(seconds: 4));

    // ── Настройки → AI лимит ────────────────────────────────────────────
    await tester.tap(find.text('Настройки').last, warnIfMissed: false);
    await _waitFor(tester, find.text('Профиль').or(find.text('ПРОФИЛЬ')),
        reason: 'экран настроек');
    await _settle(tester, const Duration(seconds: 1));

    // Карточка ниже фолда — ListView ленивый, сначала доскролливаем.
    await tester.scrollUntilVisible(
      find.text('AI лимит'), 300,
      scrollable: find.byType(Scrollable).first,
    );
    await _settle(tester);
    await tester.tap(find.text('AI лимит').last, warnIfMissed: false);
    await _waitFor(tester, find.textContaining('использовано'),
        timeout: const Duration(seconds: 15), reason: 'квота на экране AI лимит');
    expect(find.textContaining('Сброс через'), findsOneWidget);
    await _settle(tester, const Duration(seconds: 4));

    // Назад в настройки.
    await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
    await _waitFor(tester, find.text('AI лимит'), reason: 'возврат в настройки');

    _drain(tester);
    // Отчёт: какие исключения кидало приложение по ходу прогона.
    // ignore: avoid_print
    print('=== APP EXCEPTIONS (${appExceptions.length}) ===');
    for (final e in appExceptions.take(20)) {
      // ignore: avoid_print
      print('--- $e');
    }
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
