import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/annotation.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/haptics.dart';
import 'viewer_action_sheet.dart';

/// Панель действий над выделенным фрагментом: цвета, «Заметка», «Спросить AI»,
/// «Ещё».
///
/// Она пришвартована к низу экрана, а не висит у самого выделения: на телефоне
/// всплывающее меню перекрывает как раз тот текст, который человек выделил, и
/// уезжает за край у нижних строк. Материал адаптируется к теме и остаётся
/// визуально отделённым от страницы, как панель разметки в Books и Files.
class HighlightMenu extends StatelessWidget {
  /// Уже сохранённое выделение: тогда виден текущий цвет и доступно удаление.
  final Annotation? existing;
  final ValueChanged<String> onColor;
  final VoidCallback onNote;
  final VoidCallback onAskAi;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;
  final String Function(String) t;

  /// Своя обработка «Ещё» у панели сохранённой пометки: экран прячет панель
  /// на время шторки, иначе CupertinoActionSheet открывается под ней.
  final VoidCallback? onMore;

  const HighlightMenu({
    super.key,
    required this.onColor,
    required this.onNote,
    required this.onAskAi,
    required this.onCopy,
    required this.t,
    this.existing,
    this.onDelete,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface.withValues(
          alpha: isDark ? 0.96 : 0.94,
        );

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            border: Border.all(color: adaptiveBorder(context)),
            boxShadow: cardShadow(isDark),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: adaptiveSurface2(context),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final c in highlightColors)
                      _Dot(
                        key: ValueKey('hl-color-$c'),
                        color: highlightSwatch(c),
                        selected: existing?.color == c,
                        onTap: () {
                          hapticLight();
                          onColor(c);
                        },
                      ),
                  ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: _Action(
                icon: CupertinoIcons.text_bubble,
                label: t('hl_note'),
                active: existing?.comment != null,
                accent: primary,
                onTap: onNote,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _Action(
                icon: CupertinoIcons.sparkles,
                label: t('hl_ask_ai'),
                accent: primary,
                onTap: onAskAi,
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: _Action(
                icon: CupertinoIcons.ellipsis,
                label: t('hl_more'),
                accent: primary,
                onTap: () => (onMore ?? () => _showMore(context))(),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showMore(BuildContext context) {
    showAppActionSheet(
      context,
      cancelLabel: t('cancel'),
      actions: [
        AppActionSheetAction(
          icon: CupertinoIcons.doc_on_doc,
          label: t('copy'),
          onTap: onCopy,
        ),
        if (onDelete != null)
          AppActionSheetAction(
            icon: CupertinoIcons.delete,
            label: t('delete'),
            destructive: true,
            onTap: onDelete!,
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _Dot(
      {super.key,
      required this.color,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 44×44 по HIG — цель нажатия, цвет показан спокойным прямоугольным
      // образцом, а не ещё одним декоративным шаром.
      child: SizedBox(
        width: 48,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 38,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 2)
                  : Border.all(color: adaptiveBorder(context)),
            ),
            child: selected
                ? Icon(CupertinoIcons.checkmark_alt,
                    size: 14, color: Colors.black.withValues(alpha: 0.62))
                : null,
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
  final Color accent;
  final VoidCallback onTap;
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? accent : adaptiveText1(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        hapticSelection();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          color: active
              ? accent.withValues(alpha: 0.12)
              : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: color,
              )),
        ]),
      ),
    );
  }
}

/// Обёртка, которая показывает панель снизу с плавным появлением.
class HighlightMenuDock extends StatelessWidget {
  final Widget child;
  final bool visible;
  final EdgeInsets padding;

  const HighlightMenuDock({
    super.key,
    required this.child,
    required this.visible,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      offset: visible ? Offset.zero : const Offset(0, 0.35),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
