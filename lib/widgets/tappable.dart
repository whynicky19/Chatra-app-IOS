import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Тактильная кнопка-обёртка: даёт визуальный отклик на палец (лёгкое сжатие
/// + затемнение) там, где раньше стоял голый `GestureDetector` без ripple —
/// пользователь жал на карточку класса и не понимал, сработало ли нажатие.
///
/// `onTap == null` — виджет неактивен: не реагирует ни визуально, ни на
/// касание (как задизейбленная кнопка).
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = true,
    this.behavior,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior? behavior;
  final BorderRadius? borderRadius;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior ?? HitTestBehavior.opaque,
      onTapDown: active ? (_) => _setPressed(true) : null,
      onTapUp: active ? (_) => _setPressed(false) : null,
      onTapCancel: active ? () => _setPressed(false) : null,
      onTap: active
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _pressed && active ? 0.75 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
