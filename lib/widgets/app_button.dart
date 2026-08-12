import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'tappable.dart';

/// Смысловая роль кнопки — определяет цвет, не форму.
enum AppButtonVariant {
  /// Главное действие экрана/формы — акцентная заливка (teal/amber), белый текст.
  primary,

  /// "Второй по значимости" выбор рядом с primary (Cancel/Retract) — нейтральная
  /// заливка `adaptiveSurface2`, обычный текст. Совпадает с тем, что раньше
  /// было отдельно реализовано в `AppDialogActions.cancel` и
  /// `_BottomActionBar(secondary: true)`.
  secondary,

  /// Необратимое/опасное действие — заливка `C.red`.
  destructive,

  /// Низкая значимость: без фона и обводки, только цветной текст —
  /// текстовая ссылка-кнопка внутри шторки/диалога.
  text,
}

/// Единая кнопка приложения.
///
/// До рефакторинга в кодовой базе существовало минимум пять независимых
/// реализаций "главной кнопки": `ElevatedButtonTheme` из темы, кастомный
/// `_BottomActionBar` в assignment_detail_screen, инлайн `Tappable` +
/// `AnimatedContainer` в create_class_screen, `SheetButton` в
/// settings_shared, и ещё одна инлайн-копия в report_sheet — у каждой свой
/// радиус/паддинг/цвет disabled-состояния. `AppButton` — единственный новый
/// источник правды для этого набора паттернов; старые места должны постепенно
/// переехать на него (см. app_theme.dart AppRadii.button, куда сведены их
/// прежде разные радиусы).
///
/// Построена на [Tappable] — получает мгновенный pressed-feedback, минимум
/// 44pt интерактивной зоны и `Semantics(button: true)` бесплатно.
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

  /// Показывает спиннер вместо содержимого и блокирует тап, но НЕ затемняет
  /// фон (в отличие от истинного disabled) — так уже вело себя
  /// `AppDialogActions.busy`: кнопка остаётся "живой" по цвету, просто занята.
  final bool loading;

  /// Растянуть на всю доступную ширину (обычная форма для primary/secondary
  /// full-width CTA) или сжаться по контенту (типично для `.text`).
  final bool expand;

  /// Переопределение акцента — обычно не нужен, вариант уже задаёт цвет.
  final Color? color;
  final double minHeight;

  /// Мягкое цветное свечение под кнопкой (см. `primaryGlow` в app_theme.dart) —
  /// раньше было у `AppDialogActions`/некоторых CTA. Только для primary/destructive,
  /// и только пока кнопка действительно интерактивна (не disabled).
  final bool glow;

  /// Точечное переопределение заливки — нужно редко: например, экраны
  /// "detail" (assignment/lecture) живут в своей палитре (`detail_page_theme.dart`,
  /// не основной `adaptiveSurface2`), и secondary-кнопка там должна остаться
  /// в этой палитре, а не переехать на общий surface2.
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
        // НЕ `alignment: Alignment.center` — Container оборачивает контент во
        // ВНУТРЕННИЙ Align БЕЗ heightFactor (см. flutter/widgets/container.dart),
        // и когда родитель даёт "щедрую"/неограниченную высоту (например,
        // Scaffold.bottomNavigationBar), этот Align заполнял её целиком —
        // кнопка "Отправить работу"/"Просмотр работ" разрасталась на весь
        // экран, а тело экрана над ней схлопывалось в 0. `Center(heightFactor: 1)`
        // здесь центрирует контент по ширине (как и раньше), но НЕ разрешает
        // высоте вылезти за пределы content-height/minHeight.
        child: Center(heightFactor: 1, child: content),
      ),
    );
  }
}
