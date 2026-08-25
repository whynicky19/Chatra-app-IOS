import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../models/annotation.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/haptics.dart';
import '../../../utils/pdf_text_sanitize.dart';

/// Шторка действий по уже сохранённой пометке — в стиле приложения.
///
/// Заменяет связку из двух системных CupertinoActionSheet («действия» →
/// «цвет»): цвет здесь меняется прямо в шторке и она остаётся открытой, потому
/// что цвет и заметка — части одного действия, а не два разных похода в меню.
Future<void> showHighlightActionsSheet(
  BuildContext context, {
  required Annotation item,
  required String Function(String) t,
  required Future<void> Function(String color) onColor,
  required VoidCallback onNote,
  required VoidCallback onAskAi,
  required VoidCallback onDelete,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // Иначе шторка ограничена 9/16 экрана и содержимое (цитата + цвета +
    // действия) упирается в этот предел на невысоких экранах.
    isScrollControlled: true,
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
          child: _Body(
            item: item,
            t: t,
            onColor: onColor,
            onNote: onNote,
            onAskAi: onAskAi,
            onDelete: onDelete,
          ),
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
            child: Text(t('cancel'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.primary,
                )),
          ),
        ),
      ]),
    ),
  );
}

class _Body extends StatefulWidget {
  final Annotation item;
  final String Function(String) t;
  final Future<void> Function(String color) onColor;
  final VoidCallback onNote;
  final VoidCallback onAskAi;
  final VoidCallback onDelete;

  const _Body({
    required this.item,
    required this.t,
    required this.onColor,
    required this.onNote,
    required this.onAskAi,
    required this.onDelete,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  late String _color = widget.item.color;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final hasNote = widget.item.comment != null && widget.item.comment!.trim().isNotEmpty;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: adaptiveBorder(context),
            borderRadius: BorderRadius.circular(AppRadii.chip),
          ),
        ),
      ),
      // Сам фрагмент: по нему человек и опознаёт, какую именно пометку правит.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 3,
            height: 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: highlightSwatch(_color),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              sanitizePdfSymbols(widget.item.selectedText).trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                letterSpacing: -0.2,
                color: adaptiveText2(context),
              ),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final c in highlightColors)
            _Dot(
              color: highlightSwatch(c),
              selected: c == _color,
              onTap: () {
                hapticLight();
                setState(() => _color = c);
                widget.onColor(c);
              },
            ),
        ]),
      ),
      Divider(height: 1, indent: 20, endIndent: 20, color: adaptiveBorder(context)),
      _Tile(
        icon: CupertinoIcons.text_bubble,
        label: hasNote ? t('hl_note_edit') : t('hl_note'),
        onTap: widget.onNote,
      ),
      Divider(height: 1, indent: 20, endIndent: 20, color: adaptiveBorder(context)),
      _Tile(
        icon: CupertinoIcons.sparkles,
        label: t('hl_ask_ai'),
        onTap: widget.onAskAi,
      ),
      Divider(height: 1, indent: 20, endIndent: 20, color: adaptiveBorder(context)),
      _Tile(
        icon: CupertinoIcons.delete,
        label: t('delete'),
        destructive: true,
        onTap: widget.onDelete,
      ),
    ]);
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
      // 44 по высоте — цель нажатия по HIG, а не размер кружка.
      child: SizedBox(
        width: 56,
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
                  ? Border.all(color: adaptiveText1(context), width: 2.5)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? C.red : Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 14),
          Text(label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: destructive ? color : adaptiveText1(context),
              )),
        ]),
      ),
    );
  }
}
