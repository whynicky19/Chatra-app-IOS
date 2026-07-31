import 'package:flutter/material.dart';

/// Фирменный градиент логотипа Chatra — используется вместо плоской заливки
/// на всех местах с лого (сплэш, логин/регистрация, выбор организации, сайт).
/// Единая точка правды на случай, если оттенки понадобится подправить.
class BrandGradient {
  static const colors = [Color(0xFF40D0E4), Color(0xFF00829C)];

  static Widget mask({required Widget child}) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(bounds),
        child: child,
      );
}
