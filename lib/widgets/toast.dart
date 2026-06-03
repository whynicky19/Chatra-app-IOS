import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void showToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), shape: BoxShape.circle),
        child: Icon(
          error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          color: Colors.white, size: 17,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(msg, style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white, height: 1.3,
      ))),
    ]),
    backgroundColor: error ? C.red : C.teal,
    duration: Duration(seconds: error ? 4 : 2),
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    elevation: 10,
    behavior: SnackBarBehavior.floating,
  ));
}
