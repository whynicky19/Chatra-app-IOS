import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/haptics.dart';
import '../../utils/password_strength.dart';
import '../../widgets/app_button.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';

/// Секция настроек: капсовая подпись + сгруппированный список строк — ровно
/// та структура, что во всех системных Settings. Раньше каждый пункт был
/// самостоятельной карточкой с тенью и отступом 16px: экран читался как лента
/// не связанных между собой плашек, хотя пункты одной секции — это атрибуты
/// одного и того же (профиль, предпочтения, разделы).
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children, this.caption});

  final String? caption;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (caption != null)
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(caption!.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: adaptiveText3(context))),
        ),
      InsetGroup(children: children),
    ]);
  }
}

/// Пояснение ПОД группой — системный footer из iOS Settings. Отвечает на
/// вопрос «что вообще делают эти пункты и чем я рискую», не занимая места
/// в самих строках: подписи строк остаются короткими.
class SettingsFooter extends StatelessWidget {
  const SettingsFooter(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
      child: Text(text,
          style: TextStyle(fontSize: 13, height: 1.4, letterSpacing: -0.1, color: adaptiveText3(context))),
    );
  }
}

/// Строка внутри [SettingsGroup]: цветная плитка-значок, заголовок 17pt,
/// необязательное пояснение и справа либо значение (язык), либо переключатель,
/// либо шеврон.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.pos,
    this.sub,
    this.titleColor,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String? sub;
  final Color? titleColor;

  /// Текущее значение справа от заголовка (как «Русский» у языка в iOS).
  final String? value;

  /// Свой управляющий элемент справа (переключатель). Отменяет шеврон.
  final Widget? trailing;
  final GroupPos pos;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      onTap: onTap,
      // Разделитель начинается там, где начинается текст: 16 + 30 + 14.
      separatorInset: 60,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              // Плотный список: medium вместо semibold и мягкий цвет вместо
              // почти чёрного (см. adaptiveTextSoft) — десяток строк подряд
              // semibold-ом по #1C1C1E читался как «жирная чёрная простыня».
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4,
                  color: titleColor ?? adaptiveTextSoft(context))),
          if (sub != null) ...[
            const SizedBox(height: 1),
            Text(sub!, style: TextStyle(fontSize: 13, height: 1.3, color: adaptiveText3(context))),
          ],
        ])),
        if (trailing != null)
          trailing!
        else ...[
          if (value != null) ...[
            const SizedBox(width: 8),
            Text(value!, style: TextStyle(fontSize: 17, letterSpacing: -0.4, color: adaptiveText3(context))),
          ],
          const SizedBox(width: 6),
          Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(context).withValues(alpha: 0.8)),
        ],
      ]),
    );
  }
}

class SettingsSubScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? footer;

  /// Действие справа в баре (обновить). Симметрично кнопке «назад» слева:
  /// та же зона 44pt, тот же акцентный глиф.
  final Widget? action;

  const SettingsSubScreen({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // Структура нативного экрана: сначала бар с кнопкой «назад» одним
        // акцентным глифом, под ним — крупный заголовок отдельной строкой.
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
            child: Row(children: [
              Tappable(
                onTap: () => Navigator.pop(context),
                label: 'Назад',
                child: SizedBox(width: 44, height: 44,
                    child: Icon(CupertinoIcons.back, size: 26, color: Theme.of(context).colorScheme.primary)),
              ),
              const Spacer(),
              if (action != null) action!,
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: double.infinity, child: Text(title,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.9, height: 1.1, color: adaptiveTextSoft(context)))),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!,
                    style: TextStyle(fontSize: 15, letterSpacing: -0.2, height: 1.35, color: adaptiveText3(context))),
              ],
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: children,
          )),
          if (footer != null) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Center(child: footer),
          ),
        ]),
      ),
    );
  }
}

Future<void> openChangePassword(BuildContext context) async {
  final l = context.read<L10n>();
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const ChangePasswordSheet(),
  );
  if (result == true && context.mounted) showToast(context, l.t('password_changed'));
}

Future<void> openDeleteAccount(BuildContext context) async {
  final l = context.read<L10n>();
  // Само удаление выполняет шторка: ей нужно показать спиннер на кнопке и
  // оставить неверный пароль исправимым НА МЕСТЕ. Раньше шторка возвращала
  // пароль и закрывалась, запрос уходил уже без неё — секунду-две ничего не
  // происходило, а на ошибке пользователь получал тост и пустой экран
  // настроек, откуда всё надо было начинать заново.
  final deleted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const DeleteAccountSheet(),
  );
  if (deleted == true && context.mounted) showToast(context, l.t('account_deleted'));
}

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});
  @override State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _newFocus = FocusNode();
  bool _showCurrent = false, _showNew = false, _busy = false;
  String? _error;

  @override
  void dispose() { _current.dispose(); _new.dispose(); _newFocus.dispose(); super.dispose(); }

  bool get _longEnough => _new.text.length >= 8;
  bool get _different => _new.text.isNotEmpty && _new.text != _current.text;
  bool get _valid => _current.text.isNotEmpty && _longEnough && _different;

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (!_valid || _busy) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final err = await context.read<AuthProvider>().changePassword(_current.text, _new.text);
    if (!mounted) return;
    if (err == null) {
      hapticLight();
      Navigator.of(context).pop(true);
    } else {
      hapticMedium();
      setState(() { _busy = false; _error = l.t(err); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return SheetScaffold(
      title: l.t('change_password'),
      subtitle: l.t('change_password_sheet_sub'),
      icon: CupertinoIcons.lock_rotation,
      accent: primary,
      children: [
        SheetField(
          label: l.t('current_password'), controller: _current,
          obscure: !_showCurrent, onToggle: () => setState(() => _showCurrent = !_showCurrent),
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.next,
          onSubmitted: () => _newFocus.requestFocus(),
          // Правило «отличается от текущего» зависит и от этого поля тоже,
          // поэтому перестраиваем на каждую букву, а не только при ошибке.
          onChanged: (_) => setState(() { _error = null; }),
        ),
        const SizedBox(height: 14),
        SheetField(
          label: l.t('new_password'), controller: _new, focusNode: _newFocus,
          obscure: !_showNew, onToggle: () => setState(() => _showNew = !_showNew),
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
          onChanged: (_) => setState(() { _error = null; }),
        ),

        // Требования — не статичная подпись «минимум 8 символов» под полем, а
        // живой список: галочка загорается ровно в тот момент, когда правило
        // выполнено, поэтому заблокированная кнопка внизу никогда не остаётся
        // без объяснения (принцип «обратная связь во время ввода, а не после»).
        const SizedBox(height: 12),
        _RuleRow(ok: _longEnough, text: l.t('pw_rule_length')),
        const SizedBox(height: 7),
        _RuleRow(ok: _different, text: l.t('pw_rule_different')),

        // Шкала надёжности появляется только когда есть что оценивать.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _new.text.isEmpty
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _StrengthMeter(score: passwordScore(_new.text)),
                ),
        ),

        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _error == null ? const SizedBox(width: double.infinity) : SheetError(_error!),
        ),
        const SizedBox(height: 22),
        SheetButton(
          label: l.t('change_password'), color: primary,
          enabled: _valid && !_busy, busy: _busy, onTap: _submit,
        ),
      ],
    );
  }
}

/// Строка требования к паролю: кружок-галочка + текст. Галочка не просто
/// меняет цвет, а «прилетает» масштабом — так момент выполнения правила
/// заметен боковым зрением, пока палец на клавиатуре.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
    const d = Duration(milliseconds: 200);
    return Semantics(
      label: text,
      checked: ok,
      child: Row(children: [
        AnimatedContainer(
          duration: d,
          curve: Curves.easeOut,
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: ok ? C.green : Colors.transparent,
            shape: BoxShape.circle,
            border: ok ? null : Border.all(color: adaptiveText4(context).withValues(alpha: 0.5), width: 1.4),
          ),
          child: AnimatedScale(
            duration: d,
            curve: Curves.easeOutBack,
            scale: ok ? 1 : 0.4,
            child: AnimatedOpacity(
              duration: d,
              opacity: ok ? 1 : 0,
              child: const Icon(CupertinoIcons.checkmark_alt, size: 12, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: AnimatedDefaultTextStyle(
          duration: d,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            fontWeight: ok ? FontWeight.w500 : FontWeight.w400,
            color: ok ? adaptiveText2(context) : adaptiveText3(context),
          ),
          child: Text(text),
        )),
      ]),
    );
  }
}

/// Шкала надёжности пароля: та же шкала и те же три подписи, что на
/// регистрации (см. utils/password_strength.dart) — пользователь не должен
/// заново угадывать, что для приложения значит «сильный пароль».
class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final color = score <= 40 ? C.red : score <= 60 ? C.amberDk : C.green;
    final label = score <= 40
        ? l.t('password_weak')
        : score <= 60 ? l.t('password_medium') : l.t('password_strong');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(l.t('password_strength'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: adaptiveText3(context)))),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 220),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          child: Text(label),
        ),
      ]),
      const SizedBox(height: 7),
      // Ширина тянется к новому значению, а не перескакивает: шкала читается
      // как один непрерывный отклик на набор, а не как мигание.
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.chip),
        child: LayoutBuilder(builder: (context, box) => Stack(children: [
          Container(height: 5, width: double.infinity, color: adaptiveSurface2(context)),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: (score / 100).clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Container(
              height: 5,
              width: box.maxWidth * v,
              color: color,
            ),
          ),
        ])),
      ),
    ]);
  }
}

class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({super.key});
  @override State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final _pw = TextEditingController();
  bool _showPw = false, _busy = false;
  String? _error;

  @override
  void dispose() { _pw.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_pw.text.isEmpty || _busy) return;
    final l = context.read<L10n>();
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final err = await context.read<AuthProvider>().deleteAccount(_pw.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      hapticMedium();
      setState(() { _busy = false; _error = l.t(err); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final auth = context.read<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SheetScaffold(
      title: l.t('delete_account'),
      // Подзаголовок — конкретный адрес аккаунта, а не общая фраза: перед
      // необратимым действием пользователь обязан видеть, ЧТО именно удаляет
      // (на устройстве может быть несколько аккаунтов школы/университета).
      subtitle: auth.email.isEmpty ? null : auth.email,
      icon: CupertinoIcons.trash,
      accent: C.red,
      children: [
        // Вместо одного абзаца «все данные будут удалены» — перечень того, что
        // реально исчезнет. Абзац читается как формальность, список — как
        // цена решения.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: C.red.withValues(alpha: isDark ? 0.14 : 0.07),
            borderRadius: BorderRadius.circular(AppRadii.tile),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: C.red, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(l.t('delete_account_scope_title'),
                  style: const TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w600, letterSpacing: -0.1))),
            ]),
            const SizedBox(height: 10),
            _ScopeRow(CupertinoIcons.person_crop_circle, l.t('delete_scope_profile')),
            _ScopeRow(CupertinoIcons.book, l.t('delete_scope_classes')),
            _ScopeRow(CupertinoIcons.doc_text, l.t('delete_scope_work')),
            _ScopeRow(CupertinoIcons.sparkles, l.t('delete_scope_ai')),
            const SizedBox(height: 4),
            Text(l.t('delete_account_no_undo'),
                style: TextStyle(
                    fontSize: 12, height: 1.35, fontWeight: FontWeight.w600,
                    color: C.red.withValues(alpha: 0.85))),
          ]),
        ),
        const SizedBox(height: 16),
        SheetField(
          label: l.t('confirm_password'), controller: _pw,
          obscure: !_showPw, onToggle: () => setState(() => _showPw = !_showPw),
          accent: C.red,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: _submit,
          onChanged: (_) => setState(() { _error = null; }),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _error == null ? const SizedBox(width: double.infinity) : SheetError(_error!),
        ),
        const SizedBox(height: 22),
        SheetButton(
          label: l.t('delete_account_confirm'), color: C.red,
          enabled: _pw.text.isNotEmpty && !_busy, busy: _busy,
          onTap: _submit,
        ),
      ],
    );
  }
}

/// Пункт перечня «что будет удалено» внутри красной плашки.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Значки приглушены до 0.75: они помогают сканировать список, но
        // четыре красных глифа в полную силу превратили бы плашку в сирену.
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: C.red.withValues(alpha: 0.75)),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 13, height: 1.35, color: C.red.withValues(alpha: 0.95)))),
      ]),
    );
  }
}

class SheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final List<Widget> children;
  const SheetScaffold({super.key, required this.title, this.icon, this.subtitle,
    required this.accent, required this.children});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: C.text4.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(AppRadii.chip)))),
          if (icon != null) ...[
            Center(child: Container(width: 52, height: 52,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 24))),
            const SizedBox(height: 14),
          ],
          Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: adaptiveTextSoft(context), letterSpacing: -0.3)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.4, letterSpacing: -0.1, color: adaptiveText3(context))),
          ],
          const SizedBox(height: 22),
          ...children,
        ])),
      ),
    );
  }
}

class SheetField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? helper;

  /// Акцент фокуса — по умолчанию `colorScheme.primary`. В шторке удаления
  /// поле подсвечивается красным: цвет фокуса там часть предупреждения.
  final Color? accent;
  final List<String> autofillHints;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final VoidCallback? onSubmitted;

  const SheetField({super.key, required this.label, required this.controller, required this.obscure,
    required this.onToggle, required this.onChanged, this.helper, this.accent,
    this.autofillHints = const [], this.textInputAction = TextInputAction.done,
    this.focusNode, this.onSubmitted});

  @override
  State<SheetField> createState() => _SheetFieldState();
}

class _SheetFieldState extends State<SheetField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _own?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (_focused != _node.hasFocus) setState(() => _focused = _node.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent ?? Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 7, left: 2),
        // Подпись поля тоже подхватывает фокус: сразу видно, где ты сейчас,
        // не разглядывая рамку.
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: Theme.of(context).textTheme.titleSmall!
              .copyWith(color: _focused ? accent : adaptiveText3(context)),
          child: Text(widget.label),
        )),
      TextField(
        controller: widget.controller,
        focusNode: _node,
        obscureText: widget.obscure,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted == null ? null : (_) => widget.onSubmitted!(),
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: widget.autofillHints,
        textInputAction: widget.textInputAction,
        decoration: InputDecoration(
          hintText: '••••••••',
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.input),
            borderSide: BorderSide(color: accent, width: 1.8),
          ),
          prefixIcon: Padding(padding: const EdgeInsets.only(left: 4),
            child: Icon(CupertinoIcons.lock, size: 18,
                color: _focused ? accent : adaptiveText4(context))),
          // Tappable вместо IconButton: мгновенный отклик на нажатие пальца
          // (а не material-ripple по отпусканию) и гарантированные 44pt.
          suffixIcon: Tappable(
            onTap: () { hapticSelection(); widget.onToggle(); },
            label: widget.obscure ? 'Показать пароль' : 'Скрыть пароль',
            child: SizedBox(width: 44, height: 44,
              child: Icon(widget.obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  color: adaptiveText4(context), size: 18)),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ),
      if (widget.helper != null) Padding(padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text(widget.helper!, style: TextStyle(fontSize: 13, color: adaptiveText3(context)))),
    ]);
  }
}

class SheetError extends StatelessWidget {
  final String text;
  const SheetError(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(children: [
      const Icon(CupertinoIcons.exclamationmark_circle, color: C.red, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: const TextStyle(color: C.red, fontSize: 13, fontWeight: FontWeight.w600))),
    ]),
  );
}

class SheetButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled, busy;
  final VoidCallback onTap;
  const SheetButton({super.key, required this.label, required this.color,
    required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AppButton.primary(
      label: label,
      color: color,
      loading: busy,
      onPressed: enabled ? onTap : null,
      minHeight: 52,
    );
  }
}
