import 'package:flutter/material.dart';

/// Спокойный системный фон для основных экранов Chatra.
///
/// Статичные радиальные слои дают контенту глубину и позволяют стеклянным
/// поверхностям читать окружение, не отвлекая пользователя движущимся фоном.
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.scaffoldBackgroundColor;
    final top = Color.lerp(base, theme.colorScheme.surface, 0.22)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, base],
        ),
      ),
      child: child,
    );
  }
}
