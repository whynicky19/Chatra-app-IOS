import 'package:flutter/material.dart';

/// Спокойный системный фон для основных экранов Chatra.
///
/// Статичные радиальные слои дают контенту глубину и позволяют стеклянным
/// поверхностям читать окружение, не отвлекая пользователя движущимся фоном.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.accent});

  final Widget child;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tint = accent ?? theme.colorScheme.primary;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF08090B),
                          Color(0xFF101317),
                          Color(0xFF0A0B0E),
                        ]
                      : const [
                          Color(0xFFF9FAFC),
                          Color(0xFFF2F4F7),
                          Color(0xFFEDF3F5),
                        ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
            Positioned(
              width: 420,
              height: 420,
              top: -250,
              right: -170,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        tint.withValues(alpha: isDark ? 0.16 : 0.13),
                        tint.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              width: 360,
              height: 360,
              left: -230,
              bottom: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        tint.withValues(alpha: isDark ? 0.08 : 0.07),
                        tint.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
