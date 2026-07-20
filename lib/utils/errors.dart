import 'package:flutter/foundation.dart';
import '../services/crash_reporting.dart';

/// Логирование исключений вместо показа их пользователю.
///
/// Раньше провайдеры писали `errorMessage = 'Не удалось загрузить: $e'` и этот
/// текст уходил прямо в тост: пользователь видел русский текст независимо от
/// выбранного языка, а вместе с ним — сырой `DioException` с внутренним
/// адресом сервера. Теперь в `errorMessage` кладётся ключ локализации, а само
/// исключение попадает сюда.
///
/// Уходит в Crashlytics как **non-fatal**: приложение продолжило работать, но
/// знать о таких сбоях полезно — по ним видно, что именно ломается у реальных
/// пользователей (сеть, парсинг ответа, отсутствующие поля).
void logError(String where, Object error, [StackTrace? stack]) {
  if (kDebugMode) {
    debugPrint('[$where] $error');
    if (stack != null) debugPrint(stack.toString());
  }
  CrashReporting.recordError(error, stack, reason: where);
}
