import 'package:flutter/widgets.dart';

/// Общий таймер для [guardedPush]/[guardedPushNamed] — не per-экранный,
/// а на всё приложение: быстрый повторный тап по карточке в списке (до того
/// как отработает переход) иначе кладёт на Navigator второй push поверх
/// первого и ловит гонку с Cupertino edge-swipe-back в самом Flutter
/// ("_backGestureController != null" / дублирующиеся Hero-теги).
DateTime? _lastPushAt;

bool _shouldSwallow(Duration window) {
  final now = DateTime.now();
  if (_lastPushAt != null && now.difference(_lastPushAt!) < window) return true;
  _lastPushAt = now;
  return false;
}

/// Замена `Navigator.push`, игнорирующая повторный вызов в течение [window]
/// после предыдущего — используй в onTap карточек списка (класс, задание,
/// лекция, событие календаря и т.п.), где двойной тап реально случается.
Future<T?> guardedPush<T>(BuildContext context, Route<T> route, {Duration window = const Duration(milliseconds: 600)}) {
  if (_shouldSwallow(window)) return Future.value(null);
  return Navigator.push<T>(context, route);
}

/// Замена `Navigator.pushNamed` с той же защитой.
Future<T?> guardedPushNamed<T>(BuildContext context, String routeName, {Object? arguments, Duration window = const Duration(milliseconds: 600)}) {
  if (_shouldSwallow(window)) return Future.value(null);
  return Navigator.pushNamed<T>(context, routeName, arguments: arguments);
}
