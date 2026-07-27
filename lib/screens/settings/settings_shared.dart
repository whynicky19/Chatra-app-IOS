import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class SettingsActionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String sub;
  final Color? titleColor;
  final VoidCallback onTap;

  const SettingsActionCard({
    super.key,
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.sub,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: cardShadow(isDark),
        ),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 17, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
              color: titleColor ?? adaptiveText1(context))),
            const SizedBox(height: 1),
            Text(sub, style: const TextStyle(fontSize: 13, color: C.text4)),
          ])),
          const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
        ]),
      ),
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
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 16, 4),
            child: Row(children: [
              IconButton(
                icon: Icon(CupertinoIcons.back, color: adaptiveText1(context)),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: adaptiveText1(context), letterSpacing: -0.3)),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: const TextStyle(fontSize: 12.5, color: C.text4)),
                ],
              ])),
            ]),
          ),
          Expanded(child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
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
            borderRadius: BorderRadius.circular(12),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: C.text4.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2)))),
          if (icon != null) ...[
            Center(child: Container(width: 52, height: 52,
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: accent, size: 24))),
            const SizedBox(height: 14),
          ],
          Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: adaptiveText1(context), letterSpacing: -0.3)),
          const SizedBox(height: 22),
          ...children,
        ]),
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
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text3))),
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
            onPressed: onToggle,
          ),
        ),
      ),
      if (helper != null) Padding(padding: const EdgeInsets.only(top: 6, left: 2),
        child: Text(helper!, style: const TextStyle(fontSize: 12, color: C.text4))),
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
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: enabled ? color : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Align(heightFactor: 1, child: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
          : Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: enabled ? Colors.white : C.text4))),
      ),
    );
  }
}
