import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

/// Обёртки над `HapticFeedback`, подавляющие вибрацию на Android — вибромотор
/// там физически "гудит" заметнее Taptic Engine на iOS, и отклик на каждый
/// тап в приложении ощущался навязчивым. Исключение — нижняя навигация
/// (main_shell.dart вызывает HapticFeedback.lightImpact() напрямую, в обход
/// этих обёрток): это единственное место, где вибрация на Android остаётся.
bool get _suppressed => defaultTargetPlatform == TargetPlatform.android;

void hapticSelection() {
  if (!_suppressed) HapticFeedback.selectionClick();
}

void hapticLight() {
  if (!_suppressed) HapticFeedback.lightImpact();
}

void hapticMedium() {
  if (!_suppressed) HapticFeedback.mediumImpact();
}

void hapticHeavy() {
  if (!_suppressed) HapticFeedback.heavyImpact();
}
