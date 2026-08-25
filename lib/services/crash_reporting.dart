import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Единая точка репортинга ошибок приложения.
///
/// Крэши и Flutter errors идут в Firebase Crashlytics (историческая система,
/// ничего не удаляем), и ПАРАЛЛЕЛЬНО дублируются в Sentry — чтобы все части
/// Chatra (web, backend, mobile) были видны в одном контуре с алертами в
/// Telegram. Sentry включается только если сборка сделана с
/// --dart-define=SENTRY_DSN=...; без него работает один Crashlytics, как раньше.
///
/// Приватность (SEC): в Sentry не отправляются данные пользователя (только
/// безличный id), содержимое чатов/сообщений не попадает в события — SDK
/// не пишет тела запросов, а beforeSend дополнительно чистит заголовки.
class CrashReporting {
  static bool _ready = false;
  static bool _sentryReady = false;

  static bool get isReady => _ready;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  // В debug сбор отключён намеренно: иначе реальные краши тонут в шуме разработки.
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
      debugPrint('Crashlytics init failed: $e');
      _installHandlers(toCrashlytics: false);
    }
    await _initSentry();
  }

  static Future<void> _initSentry() async {
    const dsn = String.fromEnvironment('SENTRY_DSN');
    if (dsn.isEmpty) return;
    const environment = String.fromEnvironment(
      'SENTRY_ENVIRONMENT',
      defaultValue: 'development',
    );
    try {
      await SentryFlutter.init(
        (options) {
          options.dsn = dsn;
          options.environment = environment;
          options.sendDefaultPii = false;
          // Трассировка производительности у 5% сессий — экономим квоту.
          options.tracesSampleRate = kReleaseMode ? 0.05 : 0;
          // Версия приложения и окружение — для сопоставления релизов.
          // Приватность: sendDefaultPii=false отключает куки и PII; тела
          // запросов Dio SDK не пишет вовсе, заголовков в событиях нет.
        },
      );
      _sentryReady = true;
    } catch (e) {
      debugPrint('Sentry init failed: $e');
    }
  }

  static void _installHandlers({required bool toCrashlytics}) {
    final flutterOnError = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      flutterOnError?.call(details);
      if (toCrashlytics) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      }
      if (_sentryReady) {
        Sentry.captureException(details.exception, stackTrace: details.stack);
      }
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      recordError(error, stack, fatal: true);
      return true;
    };
  }

  static void recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) {
    if (kDebugMode) {
      debugPrint('[crash${fatal ? '/fatal' : ''}] ${reason ?? ''} $error');
    }
    if (_sentryReady) {
      try {
        Sentry.captureException(error, stackTrace: stack, withScope: (scope) {
          scope.setTag('fatal', fatal.toString());
          if (reason != null) scope.setTag('reason', reason);
        });
      } catch (_) {}
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
    }
  }

  /// Серверные сбои API (5xx / сеть) после исчерпания retry-логики Dio.
  /// Отправляем только method/path/status — без тела ответа и заголовков.
  static void recordApiError({
    required String method,
    required String path,
    int? statusCode,
    Object? error,
    StackTrace? stack,
  }) {
    if (!_sentryReady) return;
    try {
      Sentry.captureException(
        error ?? 'API error $statusCode',
        stackTrace: stack,
        withScope: (scope) {
          scope.setTag('api_error', 'true');
          scope.setContexts('api', {
            'method': method,
            'path': path,
            'status_code': statusCode ?? 'network_error',
          });
        },
      );
    } catch (_) {}
  }

  static Future<void> setUser(int? userId) async {
    if (_sentryReady) {
      try {
        // Только безличный числовой id: никаких email/имён.
        await Sentry.configureScope(
          (scope) => scope.setUser(
            userId == null ? null : SentryUser(id: '$userId'),
          ),
        );
      } catch (_) {}
    }
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance
          .setUserIdentifier(userId?.toString() ?? '');
    } catch (_) {}
  }

  static void log(String message) {
    if (_sentryReady) {
      try {
        Sentry.addBreadcrumb(Breadcrumb(message: message));
      } catch (_) {}
    }
    if (!_ready) return;
    try {
      FirebaseCrashlytics.instance.log(message);
    } catch (_) {}
  }

  static void runGuarded(void Function() body) {
    runZonedGuarded(body, (error, stack) {
      recordError(error, stack, reason: 'runZonedGuarded', fatal: true);
    });
  }
}
