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
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [Color(0xFF0B0B0D), Color(0xFF101012)]
              : const [Color(0xFFF7F7FA), Color(0xFFF2F2F7)],
        ),
      ),
      child: child,
    );
  }
}
