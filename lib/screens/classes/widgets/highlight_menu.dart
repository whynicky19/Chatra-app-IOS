import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';

import '../../../models/annotation.dart';
import '../../../utils/haptics.dart';
import 'viewer_action_sheet.dart';

/// Панель действий над выделенным фрагментом: цвета, «Заметка», «Спросить AI»,
/// «Ещё».
///
/// Она пришвартована к низу экрана, а не висит у самого выделения: на телефоне
/// всплывающее меню перекрывает как раз тот текст, который человек выделил, и
/// уезжает за край у нижних строк. Тёмная карточка поверх светлой страницы
/// читается как отдельный слой управления — так же, как панель разметки в
/// Books и Files.
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
    const surface = Color(0xFF2A2A2E);
    final divider = CupertinoColors.white.withValues(alpha: 0.12);

    // Поверхность непрозрачная намеренно: сквозь полупрозрачную панель с
    // blur просвечивала жёлтая подсветка только что созданной пометки, если
    // выделение лежало у нижнего края страницы — под подписями кнопок
    // проступали жёлтые полосы.
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.black.withValues(alpha: 0.28),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (final c in highlightColors)
                _Dot(
                  key: ValueKey('hl-color-$c'),
                  color: highlightSwatch(c),
                  selected: existing?.color == c,
                  onTap: () { hapticLight(); onColor(c); },
                ),
            ]),
            const SizedBox(height: 10),
            Container(height: 1, color: divider),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: _Action(
                icon: CupertinoIcons.text_bubble,
                label: t('hl_note'),
                active: existing?.comment != null,
                onTap: onNote,
              )),
              Container(width: 1, height: 30, color: divider),
              Expanded(child: _Action(
                icon: CupertinoIcons.sparkles,
                label: t('hl_ask_ai'),
                onTap: onAskAi,
              )),
              Container(width: 1, height: 30, color: divider),
              Expanded(child: _Action(
                icon: CupertinoIcons.ellipsis,
                label: t('hl_more'),
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
  const _Dot({super.key, required this.color, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 44×44 по HIG — цель нажатия, а не размер самой точки.
      child: SizedBox(
        width: 52,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: CupertinoColors.white, width: 2.5)
                  : null,
              boxShadow: selected
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10)]
                  : null,
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
    final color = active ? const Color(0xFF7CC5F5) : CupertinoColors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () { hapticSelection(); onTap(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 5),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w500,
                letterSpacing: -0.2, color: color,
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
