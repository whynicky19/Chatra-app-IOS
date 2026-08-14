import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
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

  const SettingsSubScreen({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.footer,
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
            padding: const EdgeInsets.fromLTRB(8, 2, 16, 0),
            child: Row(children: [
              Tappable(
                onTap: () => Navigator.pop(context),
                label: 'Назад',
                child: SizedBox(width: 44, height: 44,
                    child: Icon(CupertinoIcons.back, size: 26, color: Theme.of(context).colorScheme.primary)),
              ),
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
  final auth = context.read<AuthProvider>();
  final password = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const DeleteAccountSheet(),
  );
  if (password == null || password.isEmpty || !context.mounted) return;
  final err = await auth.deleteAccount(password);
  if (!context.mounted) return;
  if (err == null) {
    showToast(context, l.t('account_deleted'));
  } else {
    showToast(context, l.t(err), error: true);
  }
}

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});
  @override State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  bool _showCurrent = false, _showNew = false, _busy = false;
  String? _error;

  @override
  void dispose() { _current.dispose(); _new.dispose(); super.dispose(); }

  bool get _valid => _current.text.isNotEmpty && _new.text.length >= 8;

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (!_valid || _busy) return;
    setState(() { _busy = true; _error = null; });
    final err = await context.read<AuthProvider>().changePassword(_current.text, _new.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() { _busy = false; _error = l.t(err); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return SheetScaffold(
      title: l.t('change_password'),
      icon: CupertinoIcons.lock_rotation,
      accent: primary,
      children: [
        SheetField(
          label: l.t('current_password'), controller: _current,
          obscure: !_showCurrent, onToggle: () => setState(() => _showCurrent = !_showCurrent),
          onChanged: (_) { if (_error != null) setState(() => _error = null); },
        ),
        const SizedBox(height: 14),
        SheetField(
          label: l.t('new_password'), controller: _new,
          obscure: !_showNew, onToggle: () => setState(() => _showNew = !_showNew),
          helper: l.t('password_min_8'),
          onChanged: (_) => setState(() { if (_error != null) _error = null; }),
        ),
        if (_error != null) SheetError(_error!),
        const SizedBox(height: 22),
        SheetButton(
          label: l.t('change_password'), color: primary,
          enabled: _valid && !_busy, busy: _busy, onTap: _submit,
        ),
      ],
    );
  }
}

class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({super.key});
  @override State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final _pw = TextEditingController();
  bool _showPw = false;

  @override
  void dispose() { _pw.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SheetScaffold(
      title: l.t('delete_account'),
      icon: CupertinoIcons.trash,
      accent: C.red,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: C.red.withValues(alpha: isDark ? 0.16 : 0.08),
            borderRadius: BorderRadius.circular(AppRadii.tile),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, color: C.red, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(l.t('delete_account_warning'),
              style: const TextStyle(fontSize: 13, color: C.red, fontWeight: FontWeight.w600, height: 1.35))),
          ]),
        ),
        const SizedBox(height: 16),
        SheetField(
          label: l.t('confirm_password'), controller: _pw,
          obscure: !_showPw, onToggle: () => setState(() => _showPw = !_showPw),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        SheetButton(
          label: l.t('delete_account_confirm'), color: C.red,
          enabled: _pw.text.isNotEmpty, busy: false,
          onTap: () => Navigator.of(context).pop(_pw.text),
        ),
      ],
    );
  }
}

class SheetScaffold extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color accent;
  final List<Widget> children;
  const SheetScaffold({super.key, required this.title, this.icon,
    required this.accent, required this.children});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
          const SizedBox(height: 22),
          ...children,
        ])),
      ),
    );
  }
}

class SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? helper;
  const SheetField({super.key, required this.label, required this.controller, required this.obscure,
    required this.onToggle, required this.onChanged, this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 7, left: 2),
        child: Text(label, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: C.text3))),
      TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: '••••••••',
          prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
            child: Icon(CupertinoIcons.lock, size: 18, color: C.text4)),
          suffixIcon: IconButton(
            icon: Icon(obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, color: C.text4, size: 18),
            tooltip: obscure ? 'Показать пароль' : 'Скрыть пароль',
            onPressed: onToggle,
          ),
        ),
      ),
      if (helper != null) Padding(padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text(helper!, style: TextStyle(fontSize: 13, color: adaptiveText3(context)))),
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
