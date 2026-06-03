import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

typedef AppColors = C;
class C {
  static const teal    = Color(0xFF00B1C9);
  static const tealDk  = Color(0xFF009AAF);
  static const tealLt  = Color(0xFFE6F9FB);
  static const bg      = Color(0xFFF4F7F9);
  static const surface = Colors.white;
  static const surface2 = Color(0xFFEEF3F5);
  static const border  = Color(0xFFDDE5EA);
  static const text1   = Color(0xFF0D2D33);
  static const text2   = Color(0xFF1E3A44);
  static const text3   = Color(0xFF4A7A86);
  static const text4   = Color(0xFF8AABB5);
  static const red     = Color(0xFFDC2626);
  static const redLt   = Color(0xFFFEE2E2);
  static const redLight  = redLt;
  static const green   = Color(0xFF16A34A);
  static const greenLt = Color(0xFFDCFCE7);
  static const greenLight = greenLt;
  static const yellow  = Color(0xFFFBBF24);
  static const tealLight = tealLt;

  static const darkBg      = Color(0xFF080F11);
  static const darkSurface  = Color(0xFF0F1A1D);
  static const darkSurface2 = Color(0xFF172229);
  static const darkBorder   = Color(0xFF1C2E38);
  static const darkText1    = Color(0xFFE8F4F6);
  static const darkText2    = Color(0xFFB0CDD4);
  static const darkTealLt   = Color(0xFF0A2228);
}

// ── Shadow helpers ─────────────────────────────────────────
List<BoxShadow> cardShadow(bool isDark) => [
  BoxShadow(color: Colors.black.withOpacity(isDark ? 0.28 : 0.07), blurRadius: 20, offset: const Offset(0, 6)),
  BoxShadow(color: Colors.black.withOpacity(isDark ? 0.12 : 0.03), blurRadius: 4,  offset: const Offset(0, 1)),
];

List<BoxShadow> tealGlow({double opacity = 0.38}) => [
  BoxShadow(color: C.teal.withOpacity(opacity), blurRadius: 22, offset: const Offset(0, 7), spreadRadius: -4),
];

List<BoxShadow> softShadow(bool isDark) => [
  BoxShadow(color: Colors.black.withOpacity(isDark ? 0.18 : 0.04), blurRadius: 12, offset: const Offset(0, 3)),
];

// ── Adaptive helpers ───────────────────────────────────────
Color adaptiveSurface2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkSurface2 : C.surface2;
}

Color adaptiveTealLt(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkTealLt : C.tealLt;
}

Color adaptiveBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkBorder : C.border;
}

Color adaptiveText1(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text1;
}

// ── Theme internals ────────────────────────────────────────
const _r16 = BorderRadius.all(Radius.circular(16));

InputDecorationTheme _input(Color fill, Color focus) => InputDecorationTheme(
  filled: true,
  fillColor: fill,
  border: OutlineInputBorder(borderRadius: _r16, borderSide: BorderSide.none),
  enabledBorder: OutlineInputBorder(borderRadius: _r16, borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(borderRadius: _r16, borderSide: BorderSide(color: focus, width: 1.8)),
  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
  hintStyle: TextStyle(color: C.text4, fontSize: 14, fontWeight: FontWeight.w400),
);

ElevatedButtonThemeData _btn() => ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
  backgroundColor: C.teal,
  foregroundColor: Colors.white,
  elevation: 0,
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2),
  shape: RoundedRectangleBorder(borderRadius: _r16),
));

const _pageTransitions = PageTransitionsTheme(builders: {
  TargetPlatform.android: CupertinoPageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
});

class AppTheme {
  static final light = ThemeData(
    brightness: Brightness.light,
    primaryColor: C.teal,
    scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.light(primary: C.teal, secondary: C.tealDk, surface: C.surface, error: C.red),
    appBarTheme: const AppBarTheme(backgroundColor: C.surface, foregroundColor: C.text1, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(color: C.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: _r16)),
    inputDecorationTheme: _input(C.surface2, C.teal),
    elevatedButtonTheme: _btn(),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: C.teal,
      side: const BorderSide(color: C.teal, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: _r16),
    )),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    pageTransitionsTheme: _pageTransitions,
    dividerColor: C.border,
  );

  static final dark = ThemeData(
    brightness: Brightness.dark,
    primaryColor: C.teal,
    scaffoldBackgroundColor: C.darkBg,
    colorScheme: ColorScheme.dark(primary: C.teal, secondary: C.tealDk, surface: C.darkSurface, error: C.red),
    appBarTheme: const AppBarTheme(backgroundColor: C.darkSurface, foregroundColor: C.darkText1, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(color: C.darkSurface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: _r16)),
    inputDecorationTheme: _input(C.darkSurface2, C.teal),
    elevatedButtonTheme: _btn(),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: C.teal,
      side: const BorderSide(color: C.teal, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: _r16),
    )),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      backgroundColor: C.darkSurface2,
    ),
    pageTransitionsTheme: _pageTransitions,
    dividerColor: C.darkBorder.withOpacity(0.5),
  );
}
