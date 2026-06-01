import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void showToast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline : Icons.check_circle, color: Colors.white, size: 18),
      SizedBox(width: 10),
      Expanded(child: Text(msg, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
    ]),
    backgroundColor: error ? C.red : C.teal,
    duration: Duration(seconds: error ? 4 : 2),
    margin: EdgeInsets.all(12),
  ));
}
