import 'package:flutter/material.dart';

class AmbientGlow extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double opacity;
  const AmbientGlow({super.key, required this.alignment, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(child: IgnorePointer(child: AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      opacity: opacity.clamp(0.0, 1.0),
      child: DecoratedBox(decoration: BoxDecoration(
        gradient: RadialGradient(
          center: alignment,
          radius: 1.1,
          colors: [color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 0.7],
        ),
      )),
    )));
  }
}
