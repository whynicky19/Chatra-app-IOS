import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ── SkeletonBox ───────────────────────────────────────────────────────────────
// Shimmering placeholder. Uses its own AnimationController so it works
// stand-alone without any parent setup.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // base: the skeleton body colour; highlight: the shimmer flash.
    final base = isDark ? C.darkSurface2 : const Color(0xFFE2E9EC);
    final highlight = isDark ? const Color(0xFF1F3540) : Colors.white;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // spotX sweeps from -2 to +2 in Alignment space.
        // Alignment(-1,0) = left widget edge; Alignment(1,0) = right edge.
        // Values outside ±1 sit off the widget, so the shimmer enters and exits smoothly.
        final spotX = -2.0 + 4.0 * _ctrl.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(spotX - 0.8, 0),
              end: Alignment(spotX + 0.8, 0),
              colors: [base, highlight, base],
            ),
          ),
        );
      },
    );
  }
}

// ── Skeleton class card ───────────────────────────────────────────────────────
// Mirrors the shape of a real class card in HomeScreen.
class SkeletonClassCard extends StatelessWidget {
  const SkeletonClassCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: cardShadow(isDark),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cover image placeholder
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SkeletonBox(width: double.infinity, height: 168, borderRadius: 0),
        ),
        // Info section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Title line
            const SkeletonBox(width: 190, height: 16, borderRadius: 8),
            const SizedBox(height: 10),
            // Meta chips
            Row(children: const [
              SkeletonBox(width: 62, height: 22, borderRadius: 8),
              SizedBox(width: 6),
              SkeletonBox(width: 90, height: 22, borderRadius: 8),
            ]),
            const SizedBox(height: 14),
            // Footer: open button + action button
            Row(children: const [
              SkeletonBox(width: 86, height: 32, borderRadius: 10),
              Spacer(),
              SkeletonBox(width: 34, height: 34, borderRadius: 10),
            ]),
          ]),
        ),
      ]),
    );
  }
}

// ── Skeleton chat row ─────────────────────────────────────────────────────────
// Mirrors the shape of a real chat list item in ChatsScreen.
class SkeletonChatRow extends StatelessWidget {
  const SkeletonChatRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: softShadow(isDark),
      ),
      child: Row(children: [
        // Avatar circle
        const SkeletonBox(width: 52, height: 52, borderRadius: 26),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: const [
              // Chat title
              Expanded(child: SkeletonBox(width: double.infinity, height: 14, borderRadius: 7)),
              SizedBox(width: 40),
              // Timestamp
              SkeletonBox(width: 32, height: 10, borderRadius: 5),
            ]),
            const SizedBox(height: 8),
            // Preview text
            const SkeletonBox(width: 150, height: 11, borderRadius: 5),
          ]),
        ),
      ]),
    );
  }
}
