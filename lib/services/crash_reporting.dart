import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashReporting {
  static bool _ready = false;

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
  }

  static void _installHandlers({required bool toCrashlytics}) {
    final flutterOnError = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      flutterOnError?.call(details);
      if (toCrashlytics) {
        FirebaseCrashlytics.instance.recordFlutterFatalError(details);
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

  static Future<void> setUser(int? userId) async {
    if (!_ready) return;
    try {
      await FirebaseCrashlytics.instance
          .setUserIdentifier(userId?.toString() ?? '');
    } catch (_) {}
  }

  static void log(String message) {
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
