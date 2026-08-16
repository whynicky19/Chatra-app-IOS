import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Строительные блоки "inset grouped list" в духе iOS Settings/Files: вместо
/// стопки отдельных плавающих карточек с тенями — одна группа со сплошной
/// заливкой, волосяными разделителями между строками и скруглением только у
/// первой/последней строки.
enum GroupPos { only, first, middle, last }

GroupPos groupPos(int index, int count) {
  if (count <= 1) return GroupPos.only;
  if (index == 0) return GroupPos.first;
  if (index == count - 1) return GroupPos.last;
  return GroupPos.middle;
}

BorderRadius groupRadius(GroupPos pos, {double radius = AppRadii.card}) {
  final r = Radius.circular(radius);
  switch (pos) {
    case GroupPos.only:
      return BorderRadius.all(r);
    case GroupPos.first:
      return BorderRadius.vertical(top: r);
    case GroupPos.last:
      return BorderRadius.vertical(bottom: r);
    case GroupPos.middle:
      return BorderRadius.zero;
  }
}

Color groupSeparator(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.07);
}

Color groupPressFill(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.045);
}

/// Толщина линии в физический пиксель — как настоящие разделители iOS.
double hairline(BuildContext context) => 1 / MediaQuery.devicePixelRatioOf(context);

/// Контейнер сгруппированной секции: заливка, скругление, волосяная рамка.
/// Строки внутри — [GroupRow] с `color: Colors.transparent` (заливку и
/// скругление даёт контейнер, строке остаются разделитель и подсветка).
class InsetGroup extends StatelessWidget {
  const InsetGroup({super.key, required this.children, this.color, this.radius = AppRadii.card});

  final List<Widget> children;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final r = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surface,
        borderRadius: r,
        border: Border.all(color: groupSeparator(context), width: hairline(context)),
      ),
      child: ClipRRect(borderRadius: r, child: Column(children: children)),
    );
  }
}

/// Позиция строки внутри [InsetGroup] (последняя — без разделителя).
GroupPos innerPos(int index, int count) => index == count - 1 ? GroupPos.last : GroupPos.middle;

/// Строка сгруппированного списка: заливка группы, скругление по [pos],
/// разделитель снизу (кроме последней) и мгновенная подсветка по нажатию.
class GroupRow extends StatefulWidget {
  const GroupRow({
    super.key,
    required this.child,
    required this.pos,
    this.onTap,
    this.onLongPress,
    this.label,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 12, 12),
    this.separatorInset = 14,
    this.color,
    this.radius = AppRadii.card,
  })  : border = false,
        shadow = false;

  const GroupRow.card({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.label,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 12, 12),
    this.color,
    this.radius = AppRadii.card,
  })  : pos = GroupPos.only,
        separatorInset = 0,
        border = true,
        shadow = true;

  final Widget child;
  final GroupPos pos;
  final bool border;
  final bool shadow;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  final String? label;
  final EdgeInsetsGeometry padding;

  final double separatorInset;
  final Color? color;
  final double radius;

  @override
  State<GroupRow> createState() => _GroupRowState();
}

class _GroupRowState extends State<GroupRow> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;
    final radius = groupRadius(widget.pos, radius: widget.radius);
    final showSeparator = widget.pos == GroupPos.first || widget.pos == GroupPos.middle;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: radius,
        border: widget.border
            ? Border.all(color: groupSeparator(context), width: hairline(context))
            : null,
        boxShadow: widget.shadow ? softShadow(isDark) : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Column(children: [
          // 90ms — отклик на палец, а не анимация: подсветка появляется
          // на нажатии (onTapDown), а не по завершении тапа.
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            color: _pressed && active ? groupPressFill(context) : Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
          if (showSeparator)
            Padding(
              padding: EdgeInsets.only(left: widget.separatorInset),
              child: Container(height: hairline(context), color: groupSeparator(context)),
            ),
        ]),
      ),
    );

    if (active) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: result,
      );
    }

    if (widget.label != null) {
      result = Semantics(label: widget.label, button: true, enabled: active, child: result);
    }
    return result;
  }
}

class GroupHeader extends StatelessWidget {
  const GroupHeader({super.key, required this.title, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: adaptiveText3(context),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing, this.padding});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.15,
              color: adaptiveText1(context),
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0, this.rise = 12});

  final Widget child;
  final int index;
  final double rise;

  @override
  Widget build(BuildContext context) {
    final ms = 240 + index.clamp(0, 6) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: ms),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}
