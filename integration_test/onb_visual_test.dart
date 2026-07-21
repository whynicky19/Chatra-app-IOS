// Визуальный прогон интро: держит каждую из трёх страниц по ~4 секунды,
// чтобы внешний цикл `xcrun simctl io booted screenshot` снял кадры.
// «Начать» не нажимаем — флаг onboarding_seen не выставляется.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:chatra_app/main.dart' as app;

Future<void> _settle(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    tester.takeException();
  }
}

Future<void> _waitFor(WidgetTester tester, Finder f) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    tester.takeException();
    if (f.evaluate().isNotEmpty) return;
  }
  fail('Не дождался $f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('интро: три страницы по 4 секунды', (tester) async {
    app.main();
    await _waitFor(tester, find.text('Далее'));
    await _settle(tester, const Duration(seconds: 4));

    await tester.tap(find.text('Далее'));
    await _settle(tester, const Duration(seconds: 4));

    await tester.tap(find.text('Далее'));
    await _waitFor(tester, find.text('Начать'));
    await _settle(tester, const Duration(seconds: 4));
  });
}
