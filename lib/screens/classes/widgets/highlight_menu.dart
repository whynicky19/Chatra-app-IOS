import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/annotation.dart';

/// Компактное плавающее меню над выделенным фрагментом: цвета, «Заметка»,
/// «Спросить AI» и «Ещё».
///
/// Своё, а не системное меню выделения: системное умеет только текстовые
/// кнопки, а здесь нужны цветные точки. Форма повторяет нативную панель iOS —
/// матовая капсула со скруглением 14, волосяная рамка и мягкая тень.
class HighlightMenu extends StatelessWidget {
  /// Уже сохранённое выделение: тогда доступны удаление и текущий цвет.
  final Annotation? existing;
  final ValueChanged<String> onColor;
  final VoidCallback onNote;
  final VoidCallback onAskAi;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final String Function(String) t;

  const HighlightMenu({
    super.key,
    required this.onColor,
    required this.onNote,
    required this.onAskAi,
    required this.onCopy,
    required this.t,
    this.existing,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = (isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemBackground)
        .withValues(alpha: 0.92);
    final divider = (isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey4)
        .withValues(alpha: isDark ? 0.35 : 0.9);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: divider, width: 1 / MediaQuery.devicePixelRatioOf(context)),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: isDark ? 0.5 : 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final c in highlightColors)
              _Dot(
                color: highlightSwatch(c),
                selected: existing?.color == c,
                onTap: () => onColor(c),
              ),
            _Divider(color: divider),
            _Action(
              icon: CupertinoIcons.pencil,
              label: t('hl_note'),
              active: existing?.comment != null,
              onTap: onNote,
            ),
            _Action(icon: CupertinoIcons.sparkles, label: t('hl_ask_ai'), onTap: onAskAi),
            _Divider(color: divider),
            _More(t: t, onCopy: onCopy, onDelete: onDelete),
          ]),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Dot({required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 44×44 по HIG — цель нажатия, а не размер самой точки.
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            width: selected ? 22 : 19,
            height: selected ? 22 : 19,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: CupertinoColors.label.resolveFrom(context), width: 2)
                  : Border.all(color: CupertinoColors.black.withValues(alpha: 0.08), width: 1),
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Action({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active
        ? CupertinoTheme.of(context).primaryColor
        : CupertinoColors.label.resolveFrom(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: color,
              )),
        ]),
      ),
    );
  }
}

class _More extends StatelessWidget {
  final String Function(String) t;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  const _More({required this.t, required this.onCopy, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () { Navigator.pop(ctx); onCopy(); },
              child: Text(t('copy')),
            ),
            if (onDelete != null)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () { Navigator.pop(ctx); onDelete!(); },
                child: Text(t('delete')),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel')),
          ),
        ),
      ),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(CupertinoIcons.ellipsis,
            size: 17, color: CupertinoColors.label.resolveFrom(context)),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 1 / MediaQuery.devicePixelRatioOf(context),
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: color,
      );
}
