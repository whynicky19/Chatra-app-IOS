import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_button.dart';

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
                  borderRadius: BorderRadius.circular(AppRadii.card),
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
    return Row(children: [
      Expanded(child: AppButton.secondary(
        label: cancelText,
        onPressed: busy ? null : onCancel,
        minHeight: 46,
      )),
      const SizedBox(width: 10),
      Expanded(child: AppButton(
        label: confirmText,
        variant: danger ? AppButtonVariant.destructive : AppButtonVariant.primary,
        onPressed: onConfirm,
        loading: busy,
        glow: true,
        minHeight: 46,
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
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveText1(ctx), letterSpacing: -0.3)),
      if (message != null && message.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(message,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: adaptiveText3(ctx), height: 1.45)),
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

class AppActionSheetAction {
  final String label;
  final IconData icon;
  final bool destructive;
  final VoidCallback onTap;
  const AppActionSheetAction({required this.label, required this.icon, required this.onTap, this.destructive = false});
}

Future<void> showAppActionSheet(
  BuildContext context, {
  required List<AppActionSheetAction> actions,
  required String cancelText,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(isDark),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(width: 36, height: 4,
                decoration: BoxDecoration(color: adaptiveBorder(ctx), borderRadius: BorderRadius.circular(AppRadii.chip))),
            ),
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 20, endIndent: 20, color: adaptiveBorder(ctx)),
              _AppActionSheetTile(action: actions[i]),
            ],
          ]),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Theme.of(ctx).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              boxShadow: cardShadow(isDark),
            ),
            child: Text(cancelText, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Theme.of(ctx).colorScheme.primary)),
          ),
        ),
      ]),
    ),
  );
}

class _AppActionSheetTile extends StatelessWidget {
  final AppActionSheetAction action;
  const _AppActionSheetTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final color = action.destructive ? C.red : Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () { Navigator.pop(context); action.onTap(); },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Icon(action.icon, size: 19, color: color),
          const SizedBox(width: 14),
          Text(action.label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: action.destructive ? color : adaptiveText1(context))),
        ]),
      ),
    );
  }
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
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveText1(ctx), letterSpacing: -0.3)),
      if (message != null && message.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: adaptiveText3(ctx), height: 1.45)),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        autofocus: true,
        style: const TextStyle(fontSize: 15),
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
