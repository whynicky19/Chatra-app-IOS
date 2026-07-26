import 'package:flutter/material.dart';

/// Общая тёмная/светлая палитра для полноэкранных страниц лекции/задания —
/// отдельная от основной темы приложения (там #F2F2F7/#1C1C1E), т.к. дизайн
/// специально просил plain-black фон в духе Apple Notes/Files, а не серый.
Color detailBg(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF111111) : Colors.white;
}

Color detailSurface(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF6F6F7);
}

Color detailBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06);
}

Color detailText1(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white : const Color(0xFF111111);
}

Color detailText2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? const Color(0xFF9A9A9A) : const Color(0xFF6C6C70);
}

/// Акцент берётся из темы приложения (teal/amber в зависимости от типа
/// организации), а не хардкодится — иначе страница выпадает из общей темы
/// при переключении школа/не школа.
Color detailAccent(BuildContext context) => Theme.of(context).colorScheme.primary;
