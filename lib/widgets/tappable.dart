import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Минимальный размер интерактивной области по HIG (44×44pt).
const double kMinTapTarget = 44.0;

/// Кнопка-обёртка с визуальным откликом на палец (лёгкое сжатие + затемнение).
///
/// Гарантирует минимум [kMinTapTarget] по каждой стороне зоны нажатия, даже
/// если визуальный ребёнок меньше: лишняя площадь хит-теста невидима.
///
/// `onTap == null` — виджет неактивен: не реагирует ни визуально, ни на касание.
///
/// Хаптика по умолчанию выключена (opt-in через `haptic: true`), на Android
/// подавляется совсем.
///
/// `label` — accessibility-подпись ДЕЙСТВИЯ ("Открыть настройки"), а не иконки.
/// Обязателен для icon-only кнопок; для кнопок с видимым текстом оставляй null.
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = false,
    this.behavior,
    this.borderRadius,
    this.label,
    this.button = true,
    this.minSize = kMinTapTarget,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior? behavior;
  final BorderRadius? borderRadius;

  /// Accessibility-подпись действия (VoiceOver/TalkBack). См. доку класса.
  final String? label;

  /// Помечает узел как `button` для скринридера.
  final bool button;

  /// Минимальная сторона хит-зоны (по умолчанию HIG-минимум 44). На визуальный
  /// размер [child] не влияет; 0 — отключить.
  final double minSize;

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

    Widget result = GestureDetector(
      behavior: widget.behavior ?? HitTestBehavior.opaque,
      onTapDown: active ? (_) => _setPressed(true) : null,
      onTapUp: active ? (_) => _setPressed(false) : null,
      onTapCancel: active ? () => _setPressed(false) : null,
      onTap: active
          ? () {
              if (widget.haptic && defaultTargetPlatform != TargetPlatform.android) {
                HapticFeedback.selectionClick();
              }
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minSize, minHeight: widget.minSize),
        // widthFactor/heightFactor: 1 — без них Center() заполняет всё доступное
        // место родителя и утаскивает маленькую кнопку в центр «щедрого» слота.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
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
        ),
      ),
    );

    if (widget.label != null) {
      result = Semantics(
        label: widget.label,
        button: widget.button,
        enabled: active,
        excludeSemantics: true,
        child: result,
      );
    }

    return result;
  }
}
