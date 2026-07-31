import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Круговой индикатор результата в духе Apple Fitness/Activity: анимированная
/// заливка кольца при появлении, мягкое цветное свечение под кольцом вместо
/// плоской тени. Один акцентный цвет (не завязан на "полосу" результата —
/// экран задания везде использует единый голубой акцент).
class ScoreRing extends StatefulWidget {
  final num score;
  final num maxScore;
  final double size;
  final Color accentColor;

  const ScoreRing({super.key, required this.score, required this.maxScore, required this.accentColor, this.size = 200});

  @override
  State<ScoreRing> createState() => _ScoreRingState();
}

class _ScoreRingState extends State<ScoreRing> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  double get _pct => widget.maxScore <= 0 ? 0 : (widget.score / widget.maxScore).clamp(0, 1).toDouble();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _controller.forward(); });
  }

  @override
  void didUpdateWidget(covariant ScoreRing old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score || old.maxScore != widget.maxScore) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = [widget.accentColor.withValues(alpha: 0.75), widget.accentColor];

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final animatedPct = _pct * _animation.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha: (isDark ? 0.35 : 0.22) * _animation.value),
                blurRadius: widget.size * 0.22,
                spreadRadius: -widget.size * 0.03,
                offset: Offset(0, widget.size * 0.06),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _RingPainter(
              progress: animatedPct,
              colors: colors,
              trackColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.055),
            ),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${widget.score}',
                    style: TextStyle(fontSize: widget.size * 0.24, fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF111111), height: 1, letterSpacing: -0.5)),
                Text('/ ${widget.maxScore}',
                    style: TextStyle(fontSize: widget.size * 0.10, fontWeight: FontWeight.w600, color: const Color(0xFF8E8E93))),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;
  final Color trackColor;

  _RingPainter({required this.progress, required this.colors, required this.trackColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final strokeWidth = size.width * 0.085;
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0.001) return;

    final sweep = 2 * math.pi * progress;
    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: sweep,
      colors: colors,
      transform: const GradientRotation(-math.pi / 2),
    );
    final fg = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.colors[0] != colors[0] ||
      oldDelegate.colors[1] != colors[1];
}
