import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

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

/// Базовая "сгруппированная" карточка в духе iOS Settings/Files — заливка
/// плюс волосяная рамка вместо тени. Тень убрана осознанно: на белом фоне
/// страницы (detailBg) она читалась как "приподнятая плитка" из Material, а
/// сгруппированные секции iOS лежат в плоскости страницы, отделяясь только
/// заливкой и линией толщиной в физический пиксель.
Widget sectionCard(BuildContext context, bool isDark, {required List<Widget> children, EdgeInsetsGeometry? padding}) {
  return Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: detailSurface(context),
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.of(context).devicePixelRatio),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );
}

/// Заголовок секции внутри [sectionCard]. Один стиль на все страницы: раньше
/// те же по смыслу заголовки жили с разными кеглями/весами (16/w700, 13/w800,
/// 13/w600) в трёх местах одного экрана.
TextStyle cardTitleStyle(BuildContext context) => TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w600,
  letterSpacing: -0.3,
  color: detailText1(context),
);

/// Подпись НАД сгруппированной секцией (заголовок группы в iOS): мелкий кегль
/// капсом с положительным трекингом — обратное правило к крупным заголовкам,
/// мелкий текст нуждается в чуть большем межбуквенном расстоянии.
TextStyle sectionCaptionStyle(BuildContext context) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.6,
  color: detailText2(context),
);

/// Подпись-метка внутри карточки (над списком файлов, под заголовком).
TextStyle cardCaptionStyle(BuildContext context) => TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.1,
  color: detailText2(context),
);

/// Основной текст страницы (описание задания, тело лекции): 17pt — размер
/// body в iOS, с просторным интерлиньяжем для длинных абзацев.
TextStyle detailBodyStyle(BuildContext context) => TextStyle(
  fontSize: 17,
  height: 1.55,
  letterSpacing: -0.2,
  color: detailText1(context),
);
