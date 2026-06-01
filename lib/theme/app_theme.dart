import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

typedef AppColors = C;
class C {
  static const teal = Color(0xFF00B1C9);
  static const tealDk = Color(0xFF009AAF);
  static const tealLt = Color(0xFFE6F9FB);
  static const bg = Color(0xFFF5F7F8);
  static const surface = Colors.white;
  static const surface2 = Color(0xFFF0F4F5);
  static const border = Color(0xFFE2E8F0);
  static const text1 = Color(0xFF0D2D33);
  static const text2 = Color(0xFF1E3A44);
  static const text3 = Color(0xFF4A7A86);
  static const text4 = Color(0xFF7AABB5);
  static const red = Color(0xFFDC2626);
  static const redLt = Color(0xFFFEE2E2);
  static const redLight = redLt;
  static const green = Color(0xFF16A34A);
  static const greenLt = Color(0xFFDCFCE7);
  static const greenLight = greenLt;
  static const yellow = Color(0xFFFBBF24);
  static const tealLight = tealLt;

  // Dark theme equivalents — use these in screens to adapt properly
  static const darkBg = Color(0xFF0A1214);
  static const darkSurface = Color(0xFF111B1E);
  static const darkSurface2 = Color(0xFF1A2830);
  static const darkBorder = Color(0xFF1E3040);
  static const darkText1 = Color(0xFFE8F4F6);
  static const darkText2 = Color(0xFFB0CDD4);
  static const darkTealLt = Color(0xFF0D2D33);
}

/// Returns the correct surface2/input-fill color based on current brightness
Color adaptiveSurface2(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkSurface2 : C.surface2;
}

/// Returns adaptive tealLt (icon backgrounds, chips)
Color adaptiveTealLt(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkTealLt : C.tealLt;
}

/// Returns adaptive border color
Color adaptiveBorder(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkBorder : C.border;
}

/// Returns adaptive primary text color
Color adaptiveText1(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? C.darkText1 : C.text1;
}

const _r14 = BorderRadius.all(Radius.circular(14));

InputDecorationTheme _input(Color fill, Color focus) => InputDecorationTheme(
  filled: true, fillColor: fill,
  border: OutlineInputBorder(borderRadius: _r14, borderSide: BorderSide.none),
  enabledBorder: OutlineInputBorder(borderRadius: _r14, borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(borderRadius: _r14, borderSide: BorderSide(color: focus, width: 1.5)),
  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  hintStyle: TextStyle(color: C.text4, fontSize: 14),
);

ElevatedButtonThemeData _btn() => ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
  backgroundColor: C.teal, foregroundColor: Colors.white, elevation: 0,
  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
  shape: RoundedRectangleBorder(borderRadius: _r14),
));

const _pageTransitions = PageTransitionsTheme(builders: {
  TargetPlatform.android: CupertinoPageTransitionsBuilder(),
  TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
});

class AppTheme {
  static final light = ThemeData(
    brightness: Brightness.light, primaryColor: C.teal, scaffoldBackgroundColor: C.bg,
    colorScheme: ColorScheme.light(primary: C.teal, secondary: C.tealDk, surface: C.surface, error: C.red),
    appBarTheme: AppBarTheme(backgroundColor: C.surface, foregroundColor: C.text1, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(color: C.surface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: _r14)),
    inputDecorationTheme: _input(C.surface2, C.teal),
    elevatedButtonTheme: _btn(),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: C.teal, side: BorderSide(color: C.teal, width: 1.5), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: _r14))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: _r14)),
    pageTransitionsTheme: _pageTransitions,
    dividerColor: C.border,
  );

  static final dark = ThemeData(
    brightness: Brightness.dark, primaryColor: C.teal, scaffoldBackgroundColor: C.darkBg,
    colorScheme: ColorScheme.dark(primary: C.teal, secondary: C.tealDk, surface: C.darkSurface, error: C.red),
    appBarTheme: AppBarTheme(backgroundColor: C.darkSurface, foregroundColor: C.darkText1, elevation: 0, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(color: C.darkSurface, elevation: 0, shape: RoundedRectangleBorder(borderRadius: _r14)),
    inputDecorationTheme: _input(C.darkSurface2, C.teal),
    elevatedButtonTheme: _btn(),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(foregroundColor: C.teal, side: BorderSide(color: C.teal, width: 1.5), padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: _r14))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: _r14)),
    pageTransitionsTheme: _pageTransitions,
    dividerColor: C.darkBorder.withOpacity(0.4),
  );
}
