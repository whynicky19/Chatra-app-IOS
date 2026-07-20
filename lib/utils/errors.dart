import 'package:flutter/foundation.dart';
import '../services/crash_reporting.dart';

void logError(String where, Object error, [StackTrace? stack]) {
  if (kDebugMode) {
    debugPrint('[$where] $error');
    if (stack != null) debugPrint(stack.toString());
  }
  CrashReporting.recordError(error, stack, reason: where);
}
