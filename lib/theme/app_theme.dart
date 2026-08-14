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

  // Не чистый #000 (слишком контрастно/OLED-плоско) — тёплый тёмно-серый в
  // духе macOS/iOS, на фоне которого darkSurface (#1C1C1E) карточек всё ещё
  // заметно "приподнят". Совпадает с --bg тёмной темы сайта.
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

  // Более тёмная ступень teal/amber — только для двухцветных градиентов
  // (логотип/карточка выбора организации на org_select_screen). Раньше жили
  // как приватные `_tealGrad`/`_amberGrad` внутри самого экрана; вынесены
  // сюда, т.к. это часть фирменной палитры, а не случайный локальный подбор.
  static const tealDeep   = Color(0xFF006475);
  static const amberDeep  = Color(0xFFB45309);
  static const tealGradient  = [tealDeep, tealDk];
  static const amberGradient = [amberDeep, amber];

  // Роль/категория-акцент (учитель в admin_screen, тип уведомления
  // "новое задание" в notifications_screen) — раньше был раскидан как
  // повторяющийся hex-литерал #6366F1 в 4 местах без единого имени.
  static const indigo = Color(0xFF6366F1);

  // Третичный/приглушённый текст (см. adaptiveText3/adaptiveText4 ниже) —
  // тёмные варианты для C.text3/C.text4. darkText4 сознательно совпадает по
  // значению со светлым C.text4: на тёмной поверхности (darkSurface) этот же
  // серый даёт контраст ≈5.1:1 (проходит WCAG AA), тогда как на белом —
  // только ≈3.3:1 (не проходит). Раньше код использовал literal `C.text4`
  // без адаптации к теме и "работал" в обеих темах случайно, по совпадению
  // диапазона; здесь это же значение становится осознанным тёмным токеном.
  static const darkText3 = Color(0xFFA0A0A5);
  static const darkText4 = Color(0xFF8E8E93);
}

/// Единственный источник правды для скруглений во всём приложении.
///
/// Раньше радиусы приходили из трёх независимых мест: этих токенов,
/// приватной константы `_r16` внутри самой темы (inputs/buttons/snackbar) и
/// точечных hardcoded `BorderRadius.circular(N)` по экранам — то же самое
/// "среднее" скругление кнопки/поля на разных экранах отличалось на 2-4px
/// без причины. `_r16` удалена: `button`/`input` покрывают её роль.
class AppRadii {
  /// Крупные карточки (посты, задания, диалоги, обложки).
  static const double card = 20;
  /// Компактные строки списков (файл, уведомление, действие в меню).
  static const double tile = 14;
  /// Мелкие пилюли/бейджи/чипы.
  static const double chip = 10;
  /// Кнопки и поля ввода — единый "control"-радиус (было: кнопки местами 14
  /// через AppRadii.tile, местами 16 через _r16; поля ввода — всегда 16).
  /// Сведены к одному значению, чтобы кнопка и поле формы рядом друг с
  /// другом визуально совпадали.
  static const double button = 16;
  static const double input = button;
  /// Верхние скруглённые углы bottom sheet — уже так было в settings_shared
  /// (SheetScaffold) и report_sheet, здесь просто получает имя токена.
  static const double sheet = 24;
  /// Алиас card — центрированные диалоги (`AppDialogCard`, `showConfirmDialog`).
  static const double dialog = card;
}

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

/// Высота плавающего таб-бара main_shell (сама пилюля + отступ от базовой
/// линии) — панели, приклеенные к низу вкладки (поле ввода чата, баннер
/// блокировки), обязаны отступать хотя бы на неё, иначе уезжают под навбар.
///
/// Это НЕ полный клиренс на устройствах с Home Indicator — сама константа
/// не знает про safe-area снизу (main_shell.dart позиционирует бар как
/// `bottom: 16 + MediaQuery.paddingOf(context).bottom`, вне обычного
/// Scaffold/SafeArea). Для реального отступа над баром используй
/// [bottomBarClearance], а не эту константу напрямую.
const double kBottomBarHeight = 90;

/// Реальный клиренс над плавающим таб-баром для конкретного устройства:
/// [kBottomBarHeight] + safe-area инсет снизу (Home Indicator). На iPhone
/// с ним голого [kBottomBarHeight] не хватает — контент упирался бы в бар
/// или прятался под ним.
double bottomBarClearance(BuildContext context) =>
    kBottomBarHeight + MediaQuery.paddingOf(context).bottom;

/// Отмечает поддерево вкладки main_shell, поверх которой плавает навбар
/// (он рисуется в отдельном верхнем слое Stack — см. main_shell.dart). Тосты
/// (widgets/toast.dart) читают этот флаг, чтобы резервировать место под
/// навбар ТОЛЬКО там, где он реально есть: на отдельных экранах-маршрутах
/// (логин, детали класса, настройки...) навбара нет, и такой отступ там
/// просто задирал бы тост неоправданно высоко.
class FloatingNavBarScope extends InheritedWidget {
  const FloatingNavBarScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<FloatingNavBarScope>() != null;

  @override
  bool updateShouldNotify(FloatingNavBarScope oldWidget) => false;
}

/// Нижний отступ для панели, приклеенной к низу вкладки: с открытой
/// клавиатурой — её высота, иначе место под таб-бар.
///
/// Важно: main_shell.dart НЕ оборачивает вкладки в свой Scaffold (там
/// Material) — иначе тут получилось бы два независимых "менеджера"
/// клавиатуры (внешний Scaffold плюс этот расчёт) вразнобой по кадрам,
/// и поле ввода дёргалось при открытии/закрытии клавиатуры. Экран
/// (AiScreen) сам resizeToAvoidBottomInset: false, так что
/// MediaQuery.viewInsets.bottom здесь — живое значение, обновляется
/// каждый кадр вместе с реальной анимацией клавиатуры.
double bottomBarInset(BuildContext context) =>
    (MediaQuery.viewInsetsOf(context).bottom + 8)
        .clamp(bottomBarClearance(context), double.infinity);

Color adaptiveBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkBorder : C.border;
}

Color adaptiveText1(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text1;
}

/// Основной текст, но мягче: для ПЛОТНЫХ списков-настроек (настройки,
/// админ-панель), где строк много и они идут вплотную. На светлой теме это
/// #3A3A3C вместо почти чёрного #1C1C1E: полтора десятка строк подряд
/// semibold-ом по чистому чёрному читаются как «жирная чёрная простыня».
///
/// На тёмной теме остаётся белый: там «слишком черно» быть не может, а
/// приглушать белый до серого — значит терять контраст на главном тексте.
Color adaptiveTextSoft(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text2;
}

Color adaptiveText2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText2 : C.text2;
}

/// Третичный текст (метаданные, подписи полей) — C.text3 уже проходит
/// WCAG AA на светлом фоне (≈5.2:1), в отличие от C.text4 (см. ниже).
/// Предпочитай его вместо adaptiveText4 везде, где текст несёт смысл, а не
/// чисто декоративен.
Color adaptiveText3(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText3 : C.text3;
}

/// Самый приглушённый уровень текста. На светлом фоне C.text4 даёт лишь
/// ≈3.3:1 контраста — ниже WCAG AA (4.5:1) для обычного текста. Используй
/// ТОЛЬКО для действительно декоративных меток (таймстемпы-намёки, плейсхолдеры,
/// иконки-заглушки), никогда для содержательного текста (email, даты,
/// описания) — там нужен adaptiveText3/adaptiveText2.
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

/// ЕДИНАЯ ШКАЛА ВЕСОВ ШРИФТА. Всего четыре ступени, выше w700 не поднимаемся.
///
/// Раньше веса расходились по экранам: заголовки строк встречались и w400
/// (настройки — визуально заметно тоньше всего остального), и w500, и w600, а
/// «жирные» подписи доходили до w800/w900. Системный шрифт (SF Pro на iOS,
/// Roboto на Android) на таких весах даёт разную оптическую плотность, и
/// одинаковые по смыслу строки на разных экранах читались по-разному.
///
///  * [FontWeight.w400] — длинный текст: тело лекции, описание задания,
///    сообщения ИИ, плейсхолдеры полей. Только он.
///  * [FontWeight.w500] — второстепенное: даты, статусы, значения, мета-строки,
///    невыбранные подписи сегмент-контролов и плоские акцентные действия
///    («Показать ещё», «Вернуть», «Обновить») — они не заголовки.
///  * [FontWeight.w600] — заголовки строк и карточек, названия, подписи-капс
///    над секциями, текст кнопок. Это «нормальный» вес интерфейса.
///    Исключение — ПЛОТНЫЕ списки настроек и админ-панели: там заголовок строки
///    w500 и цвет [adaptiveTextSoft], потому что десяток строк подряд semibold-ом
///    по почти чёрному читается как «жирная простыня». Это осознанное отличие,
///    а не забытый экран.
///  * [FontWeight.w700] — только КРУПНЫЙ кегль: заголовки экранов и больших
///    секций (19pt и выше) и большие числа (баллы, токены, счётчики). На 17pt и
///    мельче bold не используется: раньше именно там веса и разъезжались —
///    на одних экранах 15pt-подписи были bold, на других medium.
///
/// Проверяется тестом test/font_weight_test.dart: он падает, если в lib/
/// появится вес тяжелее w700.
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
    final primary   = isSchool ? C.amber   : C.teal;
    final primaryDk = isSchool ? C.amberDk : C.tealDk;
    final primaryLt = isSchool ? C.amberLt : C.tealLt;
    return ThemeData(
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
        // Material 3 иначе подставляет свой дефолт scrolledUnderElevation
        // (~3) с непрозрачным shadowColor — под любым AppBar с прокручиваемым
        // содержимым (assignment_editor_screen.dart, lecture_editor_screen.dart
        // и т.п.) это рисует заметную тень/линию снизу бара при скролле, даже
        // при elevation:0. Cupertino-навбары (CupertinoSliverNavigationBar,
        // border: null) этой темы не касаются — там линия убирается иначе.
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
    final primary   = isSchool ? C.amber   : C.teal;
    final primaryDk = isSchool ? C.amberDk : C.tealDk;
    final primaryLt = isSchool ? C.darkAmberLt : C.darkTealLt;
    return ThemeData(
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
