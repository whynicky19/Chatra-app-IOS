import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../../utils/image_cache.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/network_cover_image.dart';
import '../../widgets/subject_cover.dart';
import '../../widgets/toast.dart';

/// Диалог ввода кода приглашения — оформлен в стиле остального приложения
/// (нейтральные поверхности, акцентный цвет только у кнопки и активной ячейки),
/// но без синего фона/иконки, как было раньше.
///
/// Presentation — через `showAppDialog`/`AppDialogCard` (тот же spring-bounce
/// вход, тот же `AppRadii.card`, тот же фон), что и у всех остальных диалогов
/// приложения (`showConfirmDialog`, `showInputDialog`).
Future<void> showJoinClassDialog(BuildContext context) {
  return showAppDialog(context,
    builder: (_) => const AppDialogCard(child: _JoinClassDialogContent()),
  );
}

/// Что известно про введённый код.
///
/// `unavailable` (проверить не удалось — сеть/5xx) намеренно отделён от
/// `notFound` (сервер ответил «нет такого»): раньше любая ошибка запроса
/// считалась «предмет не найден» и блокировала кнопку — при моргнувшей сети
/// пользователь не мог войти по совершенно правильному коду.
enum _Lookup { idle, checking, found, notFound, unavailable }

class _JoinClassDialogContent extends StatefulWidget {
  const _JoinClassDialogContent();
  @override
  State<_JoinClassDialogContent> createState() => _JoinClassDialogContentState();
}

class _JoinClassDialogContentState extends State<_JoinClassDialogContent> {
  static const int _length = 6;

  /// ОДНО поле на весь код, а не шесть.
  ///
  /// Раньше здесь было шесть независимых `TextField` с ручным перебросом
  /// фокуса. Так ломались ровно те вещи, которые пользователь считает
  /// само собой разумеющимися: backspace на пустой ячейке ловился только
  /// хардварной клавиатурой (`Focus.onKeyEvent`), вставка из буфера работала
  /// только в первую ячейку (`maxLength: i == 0 ? 6 : 1`), а выделение
  /// приходилось чинить руками на каждый тап. Одно поле — один каретка,
  /// одно выделение, системные backspace/вставка/undo «из коробки»;
  /// шесть ячеек ниже — просто отрисовка его значения.
  final _controller = TextEditingController();
  final _focus = FocusNode();

  Timer? _lookupDebounce;
  _Lookup _state = _Lookup.idle;
  Map<String, dynamic>? _found;
  bool _busy = false;

  /// Счётчик «встрясок» поля: меняется — [_Shaker] проигрывает анимацию.
  int _shakeTick = 0;

  String get _code => _controller.text;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCodeChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _controller.removeListener(_onCodeChanged);
    _focus.removeListener(_onFocusChanged);
    // Диалог завершает Future ещё до начала анимации закрытия — если во
    // время закрытия клавиатура тоже уходит, ещё видимые TextField
    // перестраиваются с уже задиспоженным контроллером. Даём закрывающей
    // анимации время закончиться перед dispose().
    final controller = _controller;
    final focus = _focus;
    Future.delayed(const Duration(milliseconds: 400), () {
      controller.dispose();
      focus.dispose();
    });
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  int _lastLength = 0;

  void _onCodeChanged() {
    final code = _code;
    // Отклик на КАЖДЫЙ символ, а не только на финальный: набор кода — это
    // ввод вслепую по бумажке, и подтверждение «символ принят» тактильно
    // считывается быстрее, чем глазами.
    if (code.length > _lastLength) {
      code.length == _length ? hapticLight() : hapticSelection();
    }
    _lastLength = code.length;

    _lookupDebounce?.cancel();
    if (code.length < _length) {
      setState(() { _state = _Lookup.idle; _found = null; });
      return;
    }
    setState(() { _state = _Lookup.checking; _found = null; });
    _lookupDebounce = Timer(const Duration(milliseconds: 350), () => _lookup(code));
  }

  Future<void> _lookup(String code) async {
    final api = context.read<ApiService>();
    try {
      final cls = await api.lookupClassByCode(code);
      if (!mounted || _code != code) return;
      setState(() {
        _state = _Lookup.found;
        _found = {...cls, 'title': cls['name'], 'teacher_name': cls['teacher']};
      });
    } catch (e) {
      if (!mounted || _code != code) return;
      final status = e is DioException ? e.response?.statusCode ?? 0 : 0;
      final notFound = status == 404 || status == 400;
      setState(() {
        _state = notFound ? _Lookup.notFound : _Lookup.unavailable;
        _found = null;
      });
      if (notFound) {
        // Как на экране блокировки iOS: неверный код «отряхивает» поле.
        // Ошибка сообщается там же, где сделана, и не требует читать текст.
        hapticMedium();
        setState(() => _shakeTick++);
      }
    }
  }

  /// Войти можно, когда предмет найден — или когда проверить код не удалось
  /// (тогда решает уже сам запрос на вход).
  bool get _canJoin => !_busy &&
      _code.length == _length &&
      (_state == _Lookup.found || _state == _Lookup.unavailable);

  Future<void> _join() async {
    final l = context.read<L10n>();
    final code = _code;
    if (code.length < _length) {
      showToast(context, l.t('enter_6_chars'), error: true);
      return;
    }
    final provider = context.read<ClassesProvider>();
    _focus.unfocus();
    setState(() => _busy = true);
    try {
      final cls = await provider.joinByCode(code);
      final id = cls['id'] as int;
      final title = cls['title'] ?? '';
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, '${l.t('joined_class')} $title');
      Navigator.pushNamed(context, '/class', arguments: id);
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _shakeTick++; });
      hapticMedium();
      final detail = (e is DioException && e.response?.data is Map) ? e.response?.data['detail'] : null;
      final key = detail == 'no_active_cohort'
          ? 'no_active_cohort'
          : detail == 'archived_rejoin_blocked'
              ? 'archived_rejoin_blocked'
              : 'not_found';
      showToast(context, l.t(key), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // Кнопки «закрыть» в углу больше нет: выйти из диалога и так можно
      // двумя способами (кнопка «Отмена» и тап по затемнению), а третий
      // крестик только съедал верх карточки и уводил взгляд от заголовка.
      Container(width: 60, height: 60,
        decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
        // Замок читается как «сюда не пускают»; здесь речь про код —
        // решётка называет предмет разговора прямо.
        child: Icon(CupertinoIcons.number, color: adaptiveText1(context), size: 26)),
      const SizedBox(height: 16),
      Text(l.t('join_class_title'), textAlign: TextAlign.center,
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveText1(context))),
      const SizedBox(height: 8),
      Text(l.t('join_class_hint'), textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: adaptiveText3(context), height: 1.45)),
      const SizedBox(height: 22),

      _Shaker(tick: _shakeTick, child: _CodeInput(
        controller: _controller,
        focus: _focus,
        length: _length,
        error: _state == _Lookup.notFound,
        onSubmit: () { if (_canJoin) _join(); },
      )),

      // Высота карточки меняется от состояния (пусто → спиннер → карточка
      // предмета). Без анимации диалог дёргался скачком; здесь он растёт
      // непрерывно, а содержимое сменяется кросс-фейдом.
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _status(l),
        ),
      ),

      const SizedBox(height: 20),
      AppDialogActions(
        cancelText: l.t('cancel'),
        confirmText: l.t('join_enter_class'),
        busy: _busy,
        onCancel: () => Navigator.pop(context),
        // Кнопка либо доступна, либо нет — раньше она была активна всегда и
        // на неполный код отвечала тостом «Введите 6 символов». Состояние
        // самой кнопки честнее ругательства постфактум.
        onConfirm: _canJoin ? _join : null,
      ),
    ]);
  }

  Widget _status(L10n l) {
    switch (_state) {
      case _Lookup.checking:
        return _StatusLine(
          key: const ValueKey('checking'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const CupertinoActivityIndicator(radius: 8),
            const SizedBox(width: 10),
            Text(l.t('checking_code'),
                style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
          ]),
        );
      case _Lookup.notFound:
        return _StatusLine(
          key: const ValueKey('notFound'),
          child: _Banner(text: l.t('not_found'), color: C.red,
              icon: CupertinoIcons.exclamationmark_circle_fill),
        );
      case _Lookup.unavailable:
        return _StatusLine(
          key: const ValueKey('unavailable'),
          child: _Banner(text: l.t('code_check_failed'), color: C.amberDk,
              icon: CupertinoIcons.wifi_slash),
        );
      case _Lookup.found:
        return _StatusLine(
          key: const ValueKey('found'),
          child: _FoundClassCard(data: _found!),
        );
      case _Lookup.idle:
        return const SizedBox(key: ValueKey('idle'), width: double.infinity);
    }
  }
}

/// Общий отступ сверху у любого состояния под полем — чтобы кросс-фейд между
/// ними не сдвигал содержимое по вертикали.
class _StatusLine extends StatelessWidget {
  const _StatusLine({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: SizedBox(width: double.infinity, child: Center(child: child)),
  );
}

// ── Ввод кода ────────────────────────────────────────────────────────────────

/// Шесть ячеек поверх одного невидимого поля ввода.
class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.controller,
    required this.focus,
    required this.length,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final int length;
  final bool error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final text = value.text;
          final activeIndex = text.length.clamp(0, length - 1);
          final hasFocus = focus.hasFocus;

          return Stack(children: [
            Row(children: [
              for (var i = 0; i < length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _CodeCell(
                  char: i < text.length ? text[i] : '',
                  // Активна ячейка, в которую сейчас попадёт символ. Когда код
                  // набран целиком, «следующей» нет — подсвечивать нечего.
                  active: hasFocus && i == activeIndex && text.length < length,
                  error: error,
                )),
              ],
            ]),
            // Поле лежит ПОВЕРХ ячеек и занимает всю строку: тап в любое место
            // ставит курсор, долгое нажатие даёт системную «Вставить» —
            // код из мессенджера вставляется целиком, а не по одной букве.
            Positioned.fill(child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              textAlignVertical: TextAlignVertical.center,
              showCursor: false,
              cursorColor: Colors.transparent,
              // Текст невидим — его рисуют ячейки; поле отвечает только за
              // ввод, буфер обмена и клавиатуру.
              style: const TextStyle(color: Colors.transparent, fontSize: 20, height: 1),
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => onSubmit(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(length),
                // Верхний регистр и каретка всегда в конце: код набирают
                // слева направо, а вставка длиннее шести обрезается выше.
                TextInputFormatter.withFunction((_, next) => TextEditingValue(
                  text: next.text.toUpperCase(),
                  selection: TextSelection.collapsed(offset: next.text.length),
                )),
              ],
              decoration: const InputDecoration(
                counterText: '',
                filled: false,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            )),
          ]);
        },
      ),
    );
  }
}

class _CodeCell extends StatelessWidget {
  const _CodeCell({required this.char, required this.active, required this.error});

  final String char;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final accent = error ? C.red : Theme.of(context).colorScheme.primary;
    final filled = char.isNotEmpty;

    final Color border;
    if (active) {
      border = accent;
    } else if (error) {
      border = C.red.withValues(alpha: 0.45);
    } else if (filled) {
      border = accent.withValues(alpha: 0.30);
    } else {
      border = Colors.transparent;
    }

    return AnimatedContainer(
      // 140 мс — отклик на нажатие клавиши, а не анимация: подсветка должна
      // успеть за пальцем, набирающим шесть символов подряд.
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: border, width: active ? 2 : 1.4),
      ),
      child: Center(
        child: filled
            ? _Glyph(char: char, color: error ? C.red : adaptiveText1(context))
            : (active ? _Caret(color: accent) : const SizedBox.shrink()),
      ),
    );
  }
}

/// Символ в ячейке. Появляется с крошечным перелётом — как точка пароля на
/// экране блокировки: нажатие клавиши это импульс, и отклик на него имеет
/// право быть чуть «живее» линейного (см. правило про bounce только там, где
/// был жест).
class _Glyph extends StatelessWidget {
  const _Glyph({required this.char, required this.color});

  final String char;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Text(char,
        style: TextStyle(
          fontSize: 22, fontWeight: FontWeight.w700, height: 1, color: color,
          // Моноширинные цифры: иначе «1» уже остальных, и набранный код
          // выглядит съехавшим по ячейкам.
          fontFeatures: const [FontFeature.tabularFigures()],
        ));

    if (MediaQuery.disableAnimationsOf(context)) return text;

    return TweenAnimationBuilder<double>(
      key: ValueKey(char),
      tween: Tween(begin: 0.55, end: 1),
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutBack,
      builder: (_, s, child) => Transform.scale(scale: s, child: child),
      child: text,
    );
  }
}

/// Мигающая каретка в активной пустой ячейке. Собственный контроллер живёт
/// внутри листа: он создаётся и уничтожается вместе с самой кареткой и не
/// может пережить закрытие диалога.
class _Caret extends StatefulWidget {
  const _Caret({required this.color});

  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 620))
    ..repeat(reverse: true);

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: 2, height: 24,
      decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1)),
    );
    if (MediaQuery.disableAnimationsOf(context)) return bar;
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.15)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: bar,
    );
  }
}

/// Затухающая встряска по горизонтали. Отдельный виджет, чтобы контроллер
/// анимации не зависел от жизненного цикла диалога, а `child` сохранял
/// идентичность — иначе перезапуск анимации пересобирал бы поле ввода и
/// ронял фокус вместе с клавиатурой.
class _Shaker extends StatefulWidget {
  const _Shaker({required this.tick, required this.child});

  final int tick;
  final Widget child;

  @override
  State<_Shaker> createState() => _ShakerState();
}

class _ShakerState extends State<_Shaker> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(_Shaker old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick && !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      // Затухающая синусоида: пять полупериодов с амплитудой, гаснущей к
      // концу. Ключевое — она возвращается ровно в 0, поле не «остаётся
      // сдвинутым» ни на кадр.
      builder: (_, child) {
        final t = _c.value;
        final dx = t == 0 ? 0.0 : math.sin(t * math.pi * 5) * 9 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

// ── Состояния под полем ──────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500, height: 1.35))),
      ]),
    );
  }
}

class _FoundClassCard extends StatelessWidget {
  const _FoundClassCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final teacher = (data['teacher_name'] ?? '').toString();
    return Container(
      decoration: BoxDecoration(
        color: adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: adaptiveBorder(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(height: 80, width: double.infinity,
          child: Stack(fit: StackFit.expand, children: [
            _Cover(data: data),
            SubjectIconOverlay(icon: data['cover_icon'] as String?,
                color: data['cover_color'] as String?, size: 34),
          ])),
        Padding(padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(CupertinoIcons.checkmark_circle_fill, size: 15, color: C.green),
              const SizedBox(width: 6),
              Expanded(child: Text(data['title'] ?? '',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveText1(context)),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            if (teacher.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3, left: 21),
              child: Text(teacher,
                  style: TextStyle(fontSize: 13, color: adaptiveText3(context), fontWeight: FontWeight.w600))),
          ])),
      ]),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cover = cardCoverUrl(data);
    final blank = Container(color: adaptiveSurface2(context));
    if (cover == null) return blank;

    final url = cover.toString();
    if (url.startsWith('data:')) {
      final bytes = decodeBase64Image(url);
      return bytes == null
          ? blank
          : Image.memory(bytes, fit: BoxFit.cover, width: double.infinity,
              gaplessPlayback: true, cacheWidth: 480);
    }
    return NetworkCoverImage(
      url: context.read<ApiService>().fixUrl(url),
      memCacheWidth: 480,
      errorBuilder: (_) => blank,
    );
  }
}
