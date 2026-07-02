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
        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3,
      ))),
    ]),
    backgroundColor: error ? C.red : Theme.of(context).colorScheme.primary,
    duration: Duration(seconds: error ? 4 : 2),
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    elevation: 10,
    behavior: SnackBarBehavior.floating,
  ));
}
