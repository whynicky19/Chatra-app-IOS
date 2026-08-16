import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tappable.dart';

/// Смысловая роль кнопки — определяет цвет, не форму.
enum AppButtonVariant {
  /// Главное действие экрана/формы — акцентная заливка (teal/amber), белый текст.
  primary,

  /// «Второй по значимости» рядом с primary (Отмена) — нейтральная заливка.
  secondary,

  /// Необратимое/опасное действие — заливка `C.red`.
  destructive,

  /// Низкая значимость: без фона и обводки, только цветной текст —
  /// текстовая ссылка-кнопка внутри шторки/диалога.
  text,
}

/// Единая кнопка приложения.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color,
    this.minHeight = 50,
    this.glow = false,
    this.background,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color,
    this.minHeight = 50,
    this.glow = false,
    this.background,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color,
    this.minHeight = 50,
    this.glow = false,
    this.background,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.destructive({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.color,
    this.minHeight = 50,
    this.glow = false,
    this.background,
  }) : variant = AppButtonVariant.destructive;

  const AppButton.text({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.color,
    this.minHeight = 44,
    this.glow = false,
    this.background,
  }) : variant = AppButtonVariant.text;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;

  /// Спиннер вместо содержимого; тап заблокирован, но цвет не гаснет.
  final bool loading;

  /// Растянуть на всю ширину или сжаться по контенту (типично для `.text`).
  final bool expand;

  /// Переопределение акцента — обычно не нужен, вариант уже задаёт цвет.
  final Color? color;
  final double minHeight;

  /// Мягкое цветное свечение под кнопкой. Только primary/destructive и только
  /// пока кнопка интерактивна.
  final bool glow;

  /// Точечное переопределение заливки: экраны detail живут в своей палитре
  /// (detail_page_theme.dart), и secondary-кнопка должна остаться в ней.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final disabled = onPressed == null;
    final interactive = !disabled && !loading;

    final Color bg;
    final Color fg;
    switch (variant) {
      case AppButtonVariant.primary:
        final accent = color ?? scheme.primary;
        bg = disabled ? accent.withValues(alpha: 0.35) : accent;
        fg = Colors.white;
      case AppButtonVariant.secondary:
        bg = background ?? adaptiveSurface2(context);
        fg = adaptiveText1(context).withValues(alpha: disabled ? 0.4 : 0.85);
      case AppButtonVariant.destructive:
        bg = disabled ? C.red.withValues(alpha: 0.35) : C.red;
        fg = Colors.white;
      case AppButtonVariant.text:
        bg = Colors.transparent;
        fg = (color ?? scheme.primary).withValues(alpha: disabled ? 0.4 : 1);
    }

    final content = loading
        ? CupertinoActivityIndicator(radius: 9, color: fg)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg, letterSpacing: 0.1),
                ),
              ),
            ],
          );

    return Tappable(
      onTap: interactive ? onPressed : null,
      label: label,
      minSize: minHeight,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: expand ? double.infinity : null,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.button),
          boxShadow: glow && interactive && variant != AppButtonVariant.text
              ? primaryGlow(variant == AppButtonVariant.destructive ? C.red : (color ?? scheme.primary), opacity: 0.30)
              : null,
        ),
        // Факторы обязательны: без них Center заполняет всё, что даёт родитель —
        // кнопка разрасталась по высоте в bottomNavigationBar, а `expand: false`
        // не работал совсем. При жёсткой ширине родителя факторы игнорируются.
        child: Center(heightFactor: 1, widthFactor: expand ? null : 1, child: content),
      ),
    );
  }
}
