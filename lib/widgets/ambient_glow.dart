import 'package:flutter/material.dart';

class AmbientGlow extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double opacity;
  const AmbientGlow(
      {super.key,
      required this.alignment,
      required this.color,
      required this.opacity});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
