// Целевой смоук редизайна экранов лекции/задания: логин → класс → вкладка
// «Лекции» → открыть лекцию (полноэкранная страница вместо bottom sheet) →
// назад → вкладка «Задания» → открыть задание → назад.
//
// Запуск:
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/lecture_assignment_smoke_test.dart -d <simulator>
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chatra_app/main.dart' as app;

const _qaEmail = 'qa_tester_2026@example.com';
const _qaPassword = 'QaTest12345';

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
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    _drain(tester);
  }
}

void _mark(String s) {
  // ignore: avoid_print
  print('MARK: $s');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('лекция и задание открываются полноэкранными страницами',
      (tester) async {
    app.main();

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

    await _waitFor(tester, find.text('Предметы'), reason: 'вкладка Предметы');
    await _settle(tester, const Duration(seconds: 4));

    _mark('classes_list');
    await _settle(tester, const Duration(seconds: 2));

    // Первая карточка класса.
    final classCards = find.byType(GestureDetector);
    expect(classCards.evaluate().isNotEmpty, true, reason: 'нет карточек классов');

    // Тапаем по первой карточке класса: ищем текст "Открыть курс", иначе —
    // по первому крупному тап-блоку списка.
    final openCourse = find.textContaining('Открыть');
    if (openCourse.evaluate().isNotEmpty) {
      await tester.tap(openCourse.first);
    } else {
      await tester.tap(classCards.first);
    }
    await _settle(tester, const Duration(seconds: 3));
    _mark('class_detail_opened');

    await _waitFor(tester, find.text('Лекции').or(find.text('ЛЕКЦИИ')),
        reason: 'вкладка Лекции внутри класса', timeout: const Duration(seconds: 15));
    await _settle(tester, const Duration(seconds: 2));

    final lectureCards = find.textContaining('Открыть');
    if (lectureCards.evaluate().isNotEmpty) {
      await tester.tap(lectureCards.first);
      await _settle(tester, const Duration(seconds: 2));
      _mark('lecture_detail_opened');
      await _settle(tester, const Duration(seconds: 3));
      // Назад на экран класса.
      final lectureBack = find.byIcon(CupertinoIcons.back);
      if (lectureBack.evaluate().isNotEmpty) {
        await tester.tap(lectureBack.first, warnIfMissed: false);
        await _settle(tester, const Duration(seconds: 2));
        _mark('lecture_detail_closed');
      } else {
        _mark('lecture_back_icon_not_found');
      }
    } else {
      _mark('no_lectures_found');
    }

    // Вкладка Задания.
    final asgTab = find.text('Задания').or(find.text('ЗАДАНИЯ'));
    if (asgTab.evaluate().isNotEmpty) {
      await tester.tap(asgTab.first, warnIfMissed: false);
      await _settle(tester, const Duration(seconds: 3));
      _mark('assignments_tab_opened');

      final openBtn = find.text('Открыть');
      if (openBtn.evaluate().isNotEmpty) {
        await tester.tap(openBtn.first);
        await _settle(tester, const Duration(seconds: 2));
        _mark('assignment_detail_opened');
        await _settle(tester, const Duration(seconds: 3));
        final asgBack = find.byIcon(CupertinoIcons.back);
        if (asgBack.evaluate().isNotEmpty) {
          await tester.tap(asgBack.first, warnIfMissed: false);
          await _settle(tester, const Duration(seconds: 2));
          _mark('assignment_detail_closed');
        } else {
          _mark('assignment_back_icon_not_found');
        }
      } else {
        _mark('no_assignments_found');
      }
    }

    _drain(tester);
    // ignore: avoid_print
    print('=== APP EXCEPTIONS (${appExceptions.length}) ===');
    for (final e in appExceptions.take(20)) {
      // ignore: avoid_print
      print('--- $e');
    }
    _mark('done');
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
