import 'package:flutter_test/flutter_test.dart';
import 'package:chatra_app/services/crash_reporting.dart';
import 'package:chatra_app/utils/errors.dart';

/// Crash-reporting не должен сам ронять приложение. В тестах (и на web/desktop,
/// и когда google-services.json не сконфигурирован) Firebase недоступен, поэтому
/// isReady == false — все вызовы обязаны тихо превращаться в no-op.
void main() {
  test('recordError не бросает, когда Crashlytics не инициализирован', () {
    expect(CrashReporting.isReady, isFalse);
    expect(
      () => CrashReporting.recordError(Exception('boom'), StackTrace.current,
          reason: 'test'),
      returnsNormally,
    );
  });

  test('log и setUser безопасны без инициализации', () {
    expect(() => CrashReporting.log('breadcrumb'), returnsNormally);
    expect(() => CrashReporting.setUser(42), returnsNormally);
    expect(() => CrashReporting.setUser(null), returnsNormally);
  });

  test('logError переживает отсутствие Crashlytics', () {
    expect(
      () => logError('SomeProvider.load', Exception('network'), StackTrace.current),
      returnsNormally,
    );
    // Без стектрейса — тоже валидный вызов (так его зовут провайдеры).
    expect(() => logError('SomeProvider.load', Exception('network')),
        returnsNormally);
  });

  test('runGuarded выполняет тело и ловит асинхронную ошибку', () async {
    var ran = false;
    CrashReporting.runGuarded(() {
      ran = true;
      // Ошибка в зоне не должна пробиться наружу и провалить тест.
      Future<void>.error(Exception('async boom'));
    });
    expect(ran, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
