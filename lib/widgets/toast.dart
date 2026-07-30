import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void showToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
        child: Icon(
          error ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.checkmark_circle_fill,
          color: Colors.white, size: 17,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3,
      ))),
    ]),
    // Нейтральный тёмный HUD в духе системных тостов iOS ("Copied" и т.п.),
    // а не акцентный синий — синий тут не нёс смысла (не ошибка и не
    // призыв к действию). Красный для ошибок остаётся — это системная
    // семантика, не акцент.
    backgroundColor: error ? C.red : const Color(0xE61C1C1E),
    duration: Duration(milliseconds: error ? 3000 : 1500),
    // Плавающий таб-бар (main_shell.dart) рисуется поверх вкладок в отдельном
    // верхнем слое Stack — обычного margin (14) не хватало там, где он есть,
    // тост оказывался визуально под навбаром. Но навбар есть только внутри
    // вкладок main_shell (FloatingNavBarScope) — на отдельных экранах-
    // маршрутах (логин, детали класса...) его нет, и такой отступ там просто
    // задирал бы тост слишком высоко.
    margin: EdgeInsets.fromLTRB(
      20, 0, 20, FloatingNavBarScope.of(context) ? kBottomBarHeight + 8 : 14,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.card)),
    elevation: 10,
    behavior: SnackBarBehavior.floating,
  ));
}
