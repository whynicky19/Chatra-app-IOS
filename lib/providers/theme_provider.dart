import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  // До первого выбора следуем системной теме. Раньше по умолчанию стояла
  // светлая, и пользователь с тёмным оформлением получал белую вспышку при
  // каждом запуске.
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  bool get isDark {
    if (_mode == ThemeMode.system) {
      return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    }
    return _mode == ThemeMode.dark;
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = switch (prefs.getString('theme')) {
        'dark' => ThemeMode.dark,
        'light' => ThemeMode.light,
        _ => ThemeMode.system,
      };
      notifyListeners();
    } catch (_) {}
  }

  void toggle() {
    // Явное переключение фиксирует выбор: из «системной» уходим в конкретную,
    // противоположную текущей отрисовке.
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final value = _mode == ThemeMode.dark ? 'dark' : 'light';
    SharedPreferences.getInstance()
        .then((p) => p.setString('theme', value))
        .catchError((_) => false);
  }
}
