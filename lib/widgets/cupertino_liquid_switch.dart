import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// Переключатель на движке [liquid_glass_easy], настроенный под нативный
/// iOS 26 Settings.
///
/// Эффект не воссоздаётся вручную — рендерит пакет. Параметры подобраны так,
/// чтобы визуально совпасть с системным тумблером:
/// нативные пропорции 51×31, «палец» 27, минимальный оптический бордер,
/// почти незаметная рефракция (низкий distortion, узкая полоса), слабый блюр,
/// мягкие тени, без хроматической аберрации и цветных отражений.
class CupertinoLiquidSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Цвет трека во включённом состоянии (акцент приложения).
  final Color accent;

  const CupertinoLiquidSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LiquidGlassToggle(
      value: value,
      onChanged: onChanged,
      activeColor: accent,
      // Нативные цвета выключенного трека (матовые, без свечения).
      inactiveColor: isDark ? const Color(0xFF39393D) : const Color(0xFFE9E9EA),

      // Нативные пропорции iOS: капсула 51×31, «палец» 27, ход 20.
      // Минимальный «разлив» пальца — без преувеличенной деформации.
      layout: const LiquidGlassToggleLayout(
        width: 51,
        height: 31,
        padding: 2,
        thumbWidth: 27,
        thumbHeight: 27,
        thumbExtraWidth: 5,
        thumbExtraHeight: 2,
        pinchedHeight: 24,
      ),

      // Стекло «пальца»: слабый блюр, почти невидимая рефракция, без хроматики.
      style: LiquidGlassStyle(
        appearance: LiquidGlassAppearance(
          blur: const LiquidGlassBlur(sigmaX: 1.5, sigmaY: 1.5),
          color: Colors.white.withValues(alpha: 0.10),
        ),
        refraction: const LiquidGlassRefraction(
          distortion: 0.05,
          distortionWidth: 12,
          chromaticAberration: 0.0,
          magnification: 1.0,
        ),
      ),
    );
  }
}
