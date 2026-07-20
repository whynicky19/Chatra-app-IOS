import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash-reporting через Firebase Crashlytics.
///
/// До этого приложение вообще не сообщало о падениях: после релиза о крашах
/// можно было узнать только из отзывов в сторе. Здесь собраны все три канала,
/// которыми Flutter отдаёт необработанные ошибки:
///   1. FlutterError.onError            — ошибки внутри фреймворка (build/layout)
///   2. PlatformDispatcher.onError      — необработанные async-ошибки
///   3. runZonedGuarded                 — всё остальное в зоне приложения
///
/// Работает только на Android/iOS: на web и desktop Crashlytics не поддержан,
/// поэтому там всё тихо сводится к логу в консоль.
class CrashReporting {
  static bool _ready = false;

  /// Готов ли Crashlytics принимать отчёты (false на web/desktop и до init).
  static bool get isReady => _ready;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Вызывать ПОСЛЕ Firebase.initializeApp(). Безопасно вызывать повторно.
  ///
  /// В debug сбор отключён намеренно: иначе консоль разработчика засоряет
  /// дашборд и реальные краши пользователей теряются в шуме.
  static Future<void> init() async {
    if (!_supported) {
      _installHandlers(toCrashlytics: false);
      return;
    }
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      _ready = true;
      _installHandlers(toCrashlytics: true);
    } catch (e) {
      // Firebase не сконфигурирован (например, google-services.json ещё под
      // старым bundle ID) — приложение должно стартовать без крash-репортинга.
      debugPrint('Crashlytics init failed: $e');
      _installHandlers(toCrashlytics: false);
    }
  }

  static void _installHandlers({required bool toCrashlytics}) {
    final flutterOnError = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      // Сохраняем стандартное поведение (красный экран/лог в debug).
      flutterOnError?.call(details);
      if (toCrashlytics) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error, stack, fatal: true);
      return true; // ошибка обработана — процесс не убиваем
    };
  }

  /// Отправить ошибку. [fatal] false — «non-fatal»: приложение продолжило
  /// работать (например, не загрузился список), но знать об этом полезно.
  static void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    if (kDebugMode) {
      debugPrint('[crash${fatal ? '/fatal' : ''}] ${reason ?? ''} $error');
    }
    if (!_ready) return;
    try {
      FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (_) {
      // Отчёт об ошибке не должен сам ронять приложение.
    }
  }

  /// Привязать отчёты к пользователю — в консоли Crashlytics видно, у кого
  /// именно воспроизводится краш. Пишем только id, без email и имени.
  static Future<void> setUser(int? userId) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance
          .setUserIdentifier(userId?.toString() ?? '');
    } catch (_) {}
  }

  /// Хлебные крошки: последние действия перед крашем сильно упрощают разбор.
  static void log(String message) {
    if (!_ready) return;
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
  }

  /// Запустить приложение в защищённой зоне — ловит всё, что не поймали
  /// обработчики выше.
  static void runGuarded(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      recordError(error, stack, reason: 'runZonedGuarded', fatal: true);
    });
  }
}
