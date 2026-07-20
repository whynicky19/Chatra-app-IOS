import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'dialog',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, __) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class AppDialogCard extends StatelessWidget {
  final Widget child;
  const AppDialogCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedPadding(
      padding: MediaQuery.of(context).viewInsets + const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: cardShadow(isDark),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppDialogIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const AppDialogIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 58, height: 58,
    decoration: BoxDecoration(
      gradient: RadialGradient(colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.07)]),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 27, color: color),
  );
}

class AppDialogActions extends StatelessWidget {
  final String cancelText;
  final String confirmText;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool danger;
  final bool busy;
  const AppDialogActions({
    super.key,
    required this.cancelText,
    required this.confirmText,
    required this.onCancel,
    required this.onConfirm,
    this.danger = false,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent  = danger ? C.red : primary;
    final enabled = onConfirm != null && !busy;
    return Row(children: [
      Expanded(child: GestureDetector(
        onTap: busy ? null : onCancel,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: adaptiveSurface2(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Align(heightFactor: 1, child: Text(cancelText, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: adaptiveText1(context).withValues(alpha: 0.75)))),
        ),
      )),
      const SizedBox(width: 10),
      Expanded(child: GestureDetector(
        onTap: enabled ? onConfirm : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: enabled || busy ? accent : accent.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled ? primaryGlow(accent, opacity: 0.30) : null,
          ),
          child: Align(heightFactor: 1, child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
            : Text(confirmText, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white))),
        ),
      )),
    ]);
  }
}

Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  IconData? icon,
  bool danger = false,
  required String confirmText,
  required String cancelText,
}) {
  return showAppDialog<bool>(context, builder: (ctx) {
    final accent = danger ? C.red : Theme.of(ctx).colorScheme.primary;
    return AppDialogCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AppDialogIcon(icon: icon ?? (danger ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.question_circle), color: accent),
      const SizedBox(height: 14),
      Text(title,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(ctx), letterSpacing: -0.3)),
      if (message != null && message.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: C.text4, height: 1.45)),
      ],
      const SizedBox(height: 20),
      AppDialogActions(
        cancelText: cancelText,
        confirmText: confirmText,
        danger: danger,
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () => Navigator.pop(ctx, true),
      ),
    ]));
  });
}

Future<String?> showInputDialog(
  BuildContext context, {
  required String title,
  String? message,
  IconData? icon,
  bool danger = false,
  String? hint,
  int maxLines = 3,
  required String confirmText,
  required String cancelText,
}) {
  final ctrl = TextEditingController();
  return showAppDialog<String>(context, builder: (ctx) {
    final accent = danger ? C.red : Theme.of(ctx).colorScheme.primary;
    return AppDialogCard(child: Column(mainAxisSize: MainAxisSize.min, children: [
      AppDialogIcon(icon: icon ?? CupertinoIcons.text_bubble, color: accent),
      const SizedBox(height: 14),
      Text(title,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(ctx), letterSpacing: -0.3)),
      if (message != null && message.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13.5, color: C.text4, height: 1.45)),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        autofocus: true,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(hintText: hint),
      ),
      const SizedBox(height: 16),
      AppDialogActions(
        cancelText: cancelText,
        confirmText: confirmText,
        danger: danger,
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () => Navigator.pop(ctx, ctrl.text.trim()),
      ),
    ]));
  }).whenComplete(() {
    Future.delayed(const Duration(seconds: 1), ctrl.dispose);
  });
}
