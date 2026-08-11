import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Минимальный размер интерактивной области по HIG (44×44pt).
const double kMinTapTarget = 44.0;

/// Тактильная кнопка-обёртка: даёт визуальный отклик на палец (лёгкое сжатие
/// + затемнение) там, где раньше стоял голый `GestureDetector` без ripple —
/// пользователь жал на карточку класса и не понимал, сработало ли нажатие.
///
/// Гарантирует минимум [kMinTapTarget] по каждой стороне зоны нажатия, даже
/// если визуальный ребёнок меньше (иконка 18-34px) — лишняя площадь хит-теста
/// невидима (не меняет вид ребёнка, не рисует фон/обводку), только расширяет
/// `GestureDetector`. Это explicit HIG-требование: маленькие icon-only кнопки
/// (34×34, 30×30 и мельче) физически неудобны для попадания пальцем. Там, где
/// родитель задаёт свои жёсткие constraints (например, `SizedBox` с точным
/// размером меньше 44), Flutter сам ужмёт запрошенный минимум до того, что
/// реально доступно — `Tappable` не ломает вёрстку, а расширяется настолько,
/// насколько ему позволяет контекст.
///
/// `onTap == null` — виджет неактивен: не реагирует ни визуально, ни на
/// касание (как задизейбленная кнопка).
///
/// Хаптика по умолчанию ВЫКЛЮЧЕНА: изначально стояла на каждой кнопке —
/// после массового перевода GestureDetector → Tappable это означало вибрацию
/// на буквально любой тап в приложении, что ощущалось навязчиво. Оставлена
/// как opt-in (`haptic: true`) для мест, где отклик действительно уместен
/// (свайпы/переключатели), а не как поведение по умолчанию для всех кнопок.
/// На Android вибромотор физически "гудит" заметнее, чем Taptic Engine на
/// iOS, поэтому там хаптика от Tappable подавляется совсем — вибрация
/// остаётся только у нижней навигации (main_shell.dart, отдельный код, не
/// через Tappable).
///
/// `label` — единственный источник accessibility-подписи: описывает ДЕЙСТВИЕ
/// ("Открыть настройки"), а не иконку ("шестерёнка"). Обязателен для любой
/// icon-only кнопки без видимого текста — иначе VoiceOver/TalkBack не может
/// сообщить пользователю, что делает элемент. Для кнопок с собственным
/// видимым текстом (внутри `child` уже есть `Text`) оставляй `label: null` —
/// Flutter сам прочитает текст ребёнка, дублирующая подпись только мешает.
class Tappable extends StatefulWidget {
  const Tappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.haptic = false,
    this.behavior,
    this.borderRadius,
    this.label,
    this.button = true,
    this.minSize = kMinTapTarget,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final HitTestBehavior? behavior;
  final BorderRadius? borderRadius;

  /// Accessibility-подпись действия (VoiceOver/TalkBack). См. доку класса.
  final String? label;

  /// Помечает узел как `button` для скринридера. Выключи (`false`), если это
  /// не кнопка, а, например, целая карточка-ссылка (роль `link` уместнее) —
  /// в текущей кодовой базе такого различия ещё нет, поэтому по умолчанию true.
  final bool button;

  /// Минимальная сторона хит-зоны. По умолчанию — HIG-минимум (44). Не влияет
  /// на визуальный размер [child]: лишняя площадь невидима и лишь расширяет
  /// [GestureDetector]. Передай 0, чтобы отключить (для крупных элементов,
  /// уже заведомо больше 44, это и так no-op).
  final double minSize;

  @override
  State<Tappable> createState() => _TappableState();
}

class _TappableState extends State<Tappable> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;

    Widget result = GestureDetector(
      behavior: widget.behavior ?? HitTestBehavior.opaque,
      onTapDown: active ? (_) => _setPressed(true) : null,
      onTapUp: active ? (_) => _setPressed(false) : null,
      onTapCancel: active ? () => _setPressed(false) : null,
      onTap: active
          ? () {
              if (widget.haptic && defaultTargetPlatform != TargetPlatform.android) {
                HapticFeedback.selectionClick();
              }
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minSize, minHeight: widget.minSize),
        // widthFactor/heightFactor: 1 — без них Center() по умолчанию
        // ЗАПОЛНЯЕТ всё доступное пространство родителя (а не просто
        // центрирует ребёнка внутри своего естественного размера). В
        // обычных Row/Column родитель и так даёт тесные ограничения по
        // главной оси, поэтому разница незаметна — но в "щедрых" по ширине
        // слотах (например, leading: у CupertinoSliverNavigationBar) Center
        // расползался на всю ширину навбара, визуально утаскивая маленькую
        // кнопку "назад" в центр экрана вместо стандартной позиции у края.
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: AnimatedScale(
            scale: _pressed ? widget.scale : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: _pressed && active ? 0.75 : 1.0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.label != null) {
      result = Semantics(
        label: widget.label,
        button: widget.button,
        enabled: active,
        excludeSemantics: true,
        child: result,
      );
    }

    return result;
  }
}
