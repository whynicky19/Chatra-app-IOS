import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Строительные блоки "inset grouped list" в духе iOS Settings/Files: вместо
/// стопки отдельных плавающих карточек с тенями — одна группа со сплошной
/// заливкой, волосяными разделителями между строками и скруглением только у
/// первой/последней строки.
///
/// Почему строка (а не вся группа) знает своё место: списки лекций/заданий
/// строятся лениво через `SliverChildBuilderDelegate` (30-50 элементов), и
/// оборачивать их в один общий контейнер значило бы строить все строки сразу.
/// [GroupPos] позволяет сохранить и ленивость, и вид цельной группы.
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

/// Волосяной разделитель iOS: не `dividerColor` темы (он заметно темнее и
/// читается как рамка), а едва различимая линия внутри самой группы.
Color groupSeparator(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.07);
}

/// Подсветка нажатой строки списка. Строки списка в iOS не сжимаются
/// (в отличие от кнопок — см. [Tappable]), а заливаются: масштаб на строке
/// шириной во весь экран читается как дефект, а не как отклик.
Color groupPressFill(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.045);
}

/// Толщина линии в физический пиксель — как настоящие разделители iOS.
double hairline(BuildContext context) => 1 / MediaQuery.of(context).devicePixelRatio;

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
  });

  final Widget child;
  final GroupPos pos;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Accessibility-подпись действия (см. [Tappable] о том, зачем действие, а
  /// не описание внешнего вида).
  final String? label;
  final EdgeInsetsGeometry padding;

  /// Отступ разделителя слева — выравнивается по началу текста, а не по краю
  /// карточки (iOS-конвенция: линия начинается там, где начинается контент).
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

    Widget result = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.color ?? Theme.of(context).colorScheme.surface,
        borderRadius: radius,
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

/// Заголовок секции над группой: 13pt, приглушённый — вес несёт сама группа,
/// а не подпись над ней.
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

/// Крупный заголовок раздела внутри вкладки. Отрицательный трекинг — правило
/// Apple для крупного кегля: с ростом размера буквы читаются "разъехавшимися".
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

/// Мягкое появление секции/строки: fade + едва заметный подъём, без пружины —
/// содержимое не «прилетает» от жеста пользователя, поэтому overshoot здесь
/// был бы неоправданным (правило: bounce только там, где был импульс жеста).
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0, this.rise = 12});

  final Widget child;
  final int index;
  final double rise;

  @override
  Widget build(BuildContext context) {
    // Ступенька задержки ограничена: при 30+ элементах линейный рост
    // превращал бы появление списка в затяжную волну.
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
