import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Лёгкий переключатель в стиле нативного iOS.
///
/// Ранее использовал `liquid_glass_easy` (LiquidGlassToggle), но тот держит
/// непрерывный realtime-захват экрана каждый кадр — постоянная GPU-нагрузка.
/// Здесь оптика собрана из дешёвых слоёв (градиенты + тени + тонкая кромка),
/// без блюра и без захвата: почти нулевая стоимость, вид — как системный тумблер.
/// Стеклянность выражена деликатной кромкой и внутренним бликом, чуть заметнее
/// только в момент переключения.
class CupertinoLiquidSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color accent;

  const CupertinoLiquidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  @override
  State<CupertinoLiquidSwitch> createState() => _CupertinoLiquidSwitchState();
}

class _CupertinoLiquidSwitchState extends State<CupertinoLiquidSwitch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t; // 0 = off, 1 = on
  bool _pressed = false;

  // Нативные пропорции iOS: 51×31, «палец» 27, отступ 2.
  static const double _w = 51, _h = 31, _pad = 2;
  double get _thumb => _h - _pad * 2; // 27

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: widget.value ? 1 : 0,
    );
    _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant CupertinoLiquidSwitch old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      widget.value ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;
    final offTrack = isDark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () => widget.onChanged(!widget.value),
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          // Блик заметнее лишь в движении (0 в покое, максимум в середине).
          final moving = math.sin(math.pi * t);
          final track = Color.lerp(offTrack, accent, t)!;

          return SizedBox(
            width: _w,
            height: _h,
            child: Stack(children: [
              // ── Трек: плоский матовый цвет ──
              Container(
                width: _w,
                height: _h,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(_h / 2),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06 + 0.05 * moving)
                        : Colors.black.withValues(alpha: 0.05 + 0.03 * moving),
                    width: 0.5,
                  ),
                ),
                foregroundDecoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_h / 2),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: (isDark ? 0.05 : 0.16) + 0.10 * moving),
                      Colors.white.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.035 + 0.02 * moving),
                    ],
                    stops: const [0.0, 0.28, 1.0],
                  ),
                ),
              ),

              // ── «Палец»: непрозрачный белый диск ──
              Positioned(
                top: _pad,
                left: _pad + (_w - _h) * t,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 110),
                  curve: Curves.easeOut,
                  scale: _pressed ? 0.96 : 1.0,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black.withValues(alpha: 0.04), width: 0.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 1,
                        ),
                      ],
                    ),
                    foregroundDecoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.22],
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
