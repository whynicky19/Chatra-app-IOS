import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

typedef AppColors = C;
class C {
  static const teal    = Color(0xFF00B1C9);
  static const tealDk  = Color(0xFF009AAF);
  static const tealLt  = Color(0xFFE6F9FB);

  static const bg      = Color(0xFFF2F2F7);
  static const surface = Colors.white;
  static const surface2 = Color(0xFFE5E5EA);
  static const border  = Color(0xFFD1D1D6);
  static const text1   = Color(0xFF1C1C1E);
  static const text2   = Color(0xFF3A3A3C);
  static const text3   = Color(0xFF6C6C70);
  static const text4   = Color(0xFF8E8E93);
  static const red     = Color(0xFFDC2626);
  static const redLt   = Color(0xFFFEE2E2);
  static const redLight  = redLt;
  static const green   = Color(0xFF16A34A);
  static const greenLt = Color(0xFFDCFCE7);
  static const greenLight = greenLt;
  static const yellow  = Color(0xFFFBBF24);
  static const tealLight = tealLt;
  static const yellowLt  = Color(0xFFFEF9C3);

  static const darkBg      = Color(0xFF0B0B0D);
  static const darkSurface  = Color(0xFF1C1C1E);
  static const darkSurface2 = Color(0xFF2C2C2E);
  static const darkBorder   = Color(0xFF38383A);
  static const darkText1    = Color(0xFFFFFFFF);
  static const darkText2    = Color(0xFFAEAEB2);
  static const darkTealLt   = Color(0xFF0A2228);

  static const amber      = Color(0xFFF59E0B);
  static const amberDk    = Color(0xFFD97706);
  static const amberLt    = Color(0xFFFEF3C7);
  static const darkAmberLt = Color(0xFF2A1F00);

  // ── Школьный акцент ────────────────────────────────────────────────────
  static const orange    = amberDk;      // #D97706
  static const orangeDk  = amberDeep;    // #B45309
  static const orangeLt  = Color(0xFFFBEDDF);
  static const darkOrangeLt = Color(0xFF2A1B08);

  /// Графит для градиента крупной карточки в школьной светлой теме
  /// (см. [BrandFill]) — единственное место, где школа не оранжевая.
  static const graphite   = text1;            // #1C1C1E
  static const graphiteLt = Color(0xFF3A3A3C);

  /// Цветная плитка значка в строках настроек: ФИКСИРОВАННАЯ палитра в духе
  /// системных Настроек iOS, а не акцент организации.
  static const settingsTile = teal;

  // Тёмная ступень teal/amber — только для двухцветных градиентов.
  static const tealDeep   = Color(0xFF006475);
  static const amberDeep  = Color(0xFFB45309);
  static const tealGradient  = [tealDeep, tealDk];
  static const amberGradient = [amberDeep, amber];

  // Роль/категория-акцент: учитель в admin_screen, «новое задание» в уведомлениях.
  static const indigo = Color(0xFF6366F1);

  // darkText4 намеренно равен светлому C.text4: на darkSurface этот серый даёт
  // ≈5.1:1 (WCAG AA проходит), а на белом — только ≈3.3:1 (не проходит).
  static const darkText3 = Color(0xFFA0A0A5);
  static const darkText4 = Color(0xFF8E8E93);
}

/// Единственный источник правды для скруглений во всём приложении.
class AppRadii {
  /// Крупные карточки (посты, задания, диалоги, обложки).
  static const double card = 20;
  /// Компактные строки списков (файл, уведомление, действие в меню).
  static const double tile = 14;
  /// Мелкие пилюли/бейджи/чипы.
  static const double chip = 10;
  /// Кнопки и поля ввода — единый "control"-радиус: рядом друг с другом они
  /// должны визуально совпадать.
  static const double button = 16;
  static const double input = button;
  /// Верхние скруглённые углы bottom sheet.
  static const double sheet = 24;
  /// Алиас card — центрированные диалоги (`AppDialogCard`, `showConfirmDialog`).
  static const double dialog = card;
}

/// Градиент КРУПНОЙ карточки. Отделён от `colorScheme.primary`: у школы в
/// светлой теме карточка графитовая, а оранжевый остаётся только акцентом.
@immutable
class BrandFill extends ThemeExtension<BrandFill> {
  const BrandFill({required this.gradient});

  /// Двухцветный градиент крупной карточки.
  final List<Color> gradient;

  @override
  BrandFill copyWith({List<Color>? gradient}) =>
      BrandFill(gradient: gradient ?? this.gradient);

  @override
  BrandFill lerp(BrandFill? other, double t) {
    if (other == null) return this;
    return BrandFill(gradient: [
      Color.lerp(gradient.first, other.gradient.first, t)!,
      Color.lerp(gradient.last, other.gradient.last, t)!,
    ]);
  }
}

/// [BrandFill] текущей темы. Фолбэк — университетский, чтобы виджет, поднятый
/// в тесте на голом `ThemeData()`, не падал на `!`.
BrandFill brandFill(BuildContext context) =>
    Theme.of(context).extension<BrandFill>() ?? const BrandFill(gradient: C.tealGradient);

List<BoxShadow> cardShadow(bool isDark) => [
  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07), blurRadius: 20, offset: const Offset(0, 6)),
  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.03), blurRadius: 4,  offset: const Offset(0, 1)),
];

List<BoxShadow> tealGlow({double opacity = 0.38}) => [
  BoxShadow(color: C.teal.withValues(alpha: opacity), blurRadius: 22, offset: const Offset(0, 7), spreadRadius: -4),
];

List<BoxShadow> primaryGlow(Color color, {double opacity = 0.38}) => [
  BoxShadow(color: color.withValues(alpha: opacity), blurRadius: 22, offset: const Offset(0, 7), spreadRadius: -4),
];

List<BoxShadow> softShadow(bool isDark) => [
  BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04), blurRadius: 12, offset: const Offset(0, 3)),
];

Color adaptiveSurface2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkSurface2 : C.surface2;
}

Color adaptiveTealLt(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkTealLt : C.tealLt;
}

Color adaptivePrimaryLt(BuildContext context) {
  return Theme.of(context).colorScheme.primaryContainer;
}

/// Высота плавающего таб-бара main_shell. Это НЕ полный клиренс на устройствах
/// с Home Indicator: для реального отступа бери [bottomBarClearance].
const double kBottomBarHeight = 90;

/// Реальный клиренс над таб-баром: [kBottomBarHeight] + safe-area снизу.
double bottomBarClearance(BuildContext context) =>
    kBottomBarHeight + MediaQuery.paddingOf(context).bottom;

/// Отмечает поддерево вкладки main_shell, поверх которой плавает навбар.
/// Тосты читают флаг, чтобы резервировать место под бар только там, где он есть.
class FloatingNavBarScope extends InheritedWidget {
  const FloatingNavBarScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<FloatingNavBarScope>() != null;

  @override
  bool updateShouldNotify(FloatingNavBarScope oldWidget) => false;
}

/// Нижний отступ для панели, приклеенной к низу вкладки: с открытой
/// клавиатурой — её высота, иначе 6px зазора над верхней кромкой плавающего
/// навбара (safeArea + 56). Clamp не даёт панели уехать под навбар, пока
/// клавиатура анимированно скрывается.
///
/// main_shell.dart намеренно НЕ оборачивает вкладки в свой Scaffold: иначе
/// получились бы два «менеджера» клавиатуры вразнобой и поле ввода дёргалось бы.
double bottomBarInset(BuildContext context) =>
    (MediaQuery.viewInsetsOf(context).bottom + 8)
        .clamp(MediaQuery.paddingOf(context).bottom + 62, double.infinity);

Color adaptiveBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkBorder : C.border;
}

Color adaptiveText1(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text1;
}

/// Основной текст, но мягче: для ПЛОТНЫХ списков (настройки, админ-панель).
/// На светлой теме #3A3A3C вместо почти чёрного, на тёмной — по-прежнему белый.
Color adaptiveTextSoft(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text2;
}

Color adaptiveText2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText2 : C.text2;
}

/// Третичный текст (метаданные, подписи полей): ≈5.2:1 на светлом фоне, WCAG AA
/// проходит. Предпочитай его adaptiveText4 везде, где текст несёт смысл.
Color adaptiveText3(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText3 : C.text3;
}

/// Самый приглушённый уровень: на светлом фоне лишь ≈3.3:1, ниже WCAG AA.
/// ТОЛЬКО для декоративных меток, никогда для содержательного текста.
Color adaptiveText4(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText4 : C.text4;
}

const _rInput = BorderRadius.all(Radius.circular(AppRadii.input));
const _rButton = BorderRadius.all(Radius.circular(AppRadii.button));

InputDecorationTheme _input(Color fill, Color focus) => InputDecorationTheme(
  filled: true,
  fillColor: fill,
  border: const OutlineInputBorder(borderRadius: _rInput, borderSide: BorderSide.none),
  enabledBorder: const OutlineInputBorder(borderRadius: _rInput, borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(borderRadius: _rInput, borderSide: BorderSide(color: focus, width: 1.8)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
  hintStyle: const TextStyle(color: C.text4, fontSize: 15, fontWeight: FontWeight.w400),
);

ElevatedButtonThemeData _btnFor(Color primary) => ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
  backgroundColor: primary,
  foregroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
  shape: const RoundedRectangleBorder(borderRadius: _rButton),
));

const _pageTransitions = PageTransitionsTheme(builders: {
  TargetPlatform.android: CupertinoPageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
});

/// ЕДИНАЯ ШКАЛА ВЕСОВ ШРИФТА. Четыре ступени, выше w700 не поднимаемся.
///
///  * [FontWeight.w400] — длинный текст: тело лекции, описание задания,
///    сообщения ИИ, плейсхолдеры полей.
///  * [FontWeight.w500] — второстепенное: даты, статусы, значения, мета-строки,
///    невыбранные подписи сегмент-контролов, плоские акцентные действия.
///  * [FontWeight.w600] — заголовки строк и карточек, названия, подписи-капс,
///    текст кнопок. Исключение — плотные списки настроек и админ-панели: там
///    заголовок строки w500 и цвет [adaptiveTextSoft].
///  * [FontWeight.w700] — только крупный кегль (19pt и выше) и большие числа.
///
/// Проверяется тестом test/font_weight_test.dart.
const _textTheme = TextTheme(
  displayLarge:   TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.1),
  headlineLarge:  TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.15),
  headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2),
  titleLarge:     TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.1),
  titleMedium:    TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  titleSmall:     TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  bodyLarge:      TextStyle(fontSize: 17, fontWeight: FontWeight.w400, height: 1.45),
  bodyMedium:     TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
  bodySmall:      TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.4),
  labelLarge:     TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
  labelMedium:    TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
  labelSmall:     TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
);

class AppTheme {
  static ThemeData lightFor(bool isSchool) {
    final primary   = isSchool ? C.orange   : C.teal;
    final primaryDk = isSchool ? C.orangeDk : C.tealDk;
    final primaryLt = isSchool ? C.orangeLt : C.tealLt;
    final brand = isSchool
        ? const BrandFill(gradient: [C.graphite, C.graphiteLt])
        : const BrandFill(gradient: C.tealGradient);
    return ThemeData(
      extensions: [brand],
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: C.bg,
      colorScheme: ColorScheme.light(
        primary: primary, secondary: primaryDk,
        surface: C.surface, error: C.red,
        primaryContainer: primaryLt,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: C.surface, foregroundColor: C.text1,
        elevation: 0, surfaceTintColor: Colors.transparent,
        // Без этого Material 3 подставляет свой scrolledUnderElevation (~3) и
        // рисует линию под баром при скролле даже при elevation: 0.
        scrolledUnderElevation: 0, shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: C.surface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
      ),
      inputDecorationTheme: _input(C.surface2, primary),
      elevatedButtonTheme: _btnFor(primary),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: _rButton),
      )),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: C.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null),
      ),
      textTheme: _textTheme,
      pageTransitionsTheme: _pageTransitions,
      dividerColor: C.border,
    );
  }

  static ThemeData darkFor(bool isSchool) {
    final primary   = isSchool ? C.orange   : C.teal;
    final primaryDk = isSchool ? C.orangeDk : C.tealDk;
    final primaryLt = isSchool ? C.darkOrangeLt : C.darkTealLt;
    final brand = isSchool
        ? const BrandFill(gradient: [C.orangeDk, C.orange])
        : const BrandFill(gradient: C.tealGradient);
    return ThemeData(
      extensions: [brand],
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: C.darkBg,
      colorScheme: ColorScheme.dark(
        primary: primary, secondary: primaryDk,
        surface: C.darkSurface, error: C.red,
        primaryContainer: primaryLt,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: C.darkSurface, foregroundColor: C.darkText1,
        elevation: 0, surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0, shadowColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: C.darkSurface, elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
      ),
      inputDecorationTheme: _input(C.darkSurface2, primary),
      elevatedButtonTheme: _btnFor(primary),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: _rButton),
      )),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        backgroundColor: C.darkSurface2,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: C.darkSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
        elevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : null),
      ),
      textTheme: _textTheme,
      pageTransitionsTheme: _pageTransitions,
      dividerColor: C.darkBorder.withValues(alpha: 0.5),
    );
  }

  static final light       = lightFor(false);
  static final dark        = darkFor(false);
  static final lightSchool = lightFor(true);
  static final darkSchool  = darkFor(true);
}
