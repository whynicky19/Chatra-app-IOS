import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cupertino_liquid_switch.dart';
import '../../widgets/telegram_logo.dart';
import '../../widgets/toast.dart';
import 'contact_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  late AnimationController _entry;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = context.read<AuthProvider>().fullName;
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
  }

  @override
  void dispose() { _entry.dispose(); _nameCtrl.dispose(); super.dispose(); }

  Widget _animated(Widget child, double start, double end) {
    final anim = CurvedAnimation(parent: _entry, curve: Interval(start, end, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final l         = context.watch<L10n>();
    final surface   = Theme.of(context).colorScheme.surface;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final primary   = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 100), children: [

        // ── Page title ──────────────────────────────────────────
        _animated(Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('settings'),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
              color: adaptiveText1(context), letterSpacing: -0.4, height: 1.1)),
          const SizedBox(height: 3),
          Text(l.t('settings_sub'), style: const TextStyle(fontSize: 14, color: C.text4)),
        ])), 0.0, 0.4),

        // ── Profile card ────────────────────────────────────────
        _animated(const _SectionLabel('ПРОФИЛЬ'), 0.05, 0.45),
        const SizedBox(height: 8),

        _animated(Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), boxShadow: cardShadow(isDark)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Banner + avatar
            Stack(clipBehavior: Clip.none, children: [
              Container(height: 72, decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.secondary, primary],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              )),
              Positioned(bottom: -34, left: 20, child: Container(
                width: 68, height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [primary, Theme.of(context).colorScheme.secondary], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: Border.all(color: surface, width: 3),
                ),
                child: Center(child: Text(auth.initials,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700))),
              )),
            ]),
            const SizedBox(height: 44),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(auth.fullName.isNotEmpty ? auth.fullName : auth.email,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: adaptiveText1(context)),
                  overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.card)),
                  child: Text(_roleLabel(auth.role, l),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: primary)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(auth.email, style: const TextStyle(fontSize: 13, color: C.text4)),
              // Cyrillic warning
              if (auth.fullName.isNotEmpty && !_isCyrillicName(auth.fullName)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: C.amber.withValues(alpha: isDark ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(AppRadii.chip),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 15, color: C.amberDk),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Ваше ФИО указано не на кириллице. Пожалуйста, обновите его ниже.',
                      style: TextStyle(fontSize: 12, color: C.amberDk, fontWeight: FontWeight.w600, height: 1.4),
                    )),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              _fieldLabel(l.t('full_name')),
              TextField(controller: _nameCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(
                prefixIcon: Padding(padding: EdgeInsets.only(left: 4),
                  child: Icon(CupertinoIcons.person, size: 18, color: C.text4)))),
              if (_nameCtrl.text.isNotEmpty && !_isCyrillicName(_nameCtrl.text))
                Padding(padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: C.red.withValues(alpha: isDark ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(AppRadii.chip)),
                    child: const Row(children: [
                      Icon(CupertinoIcons.xmark_circle, size: 14, color: C.red),
                      SizedBox(width: 7),
                      Expanded(child: Text('ФИО должно быть на кириллице (рус/каз)',
                        style: TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w600))),
                    ]),
                  )),
              const SizedBox(height: 14),
              _fieldLabel(l.t('email')),
              TextField(enabled: false, decoration: InputDecoration(
                hintText: auth.email,
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                  child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)))),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _saving ? null : () async {
                  setState(() => _saving = true);
                  await auth.updateProfile(_nameCtrl.text.trim());
                  if (!context.mounted) return;
                  setState(() => _saving = false);
                  showToast(context, l.t('saved'));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 50,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _saving ? null : primaryGlow(primary, opacity: 0.30),
                  ),
                  child: Center(child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Text(l.t('save_changes'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white))),
                ),
              ),
            ])),
          ]),
        ), 0.1, 0.6),

        const SizedBox(height: 24),

        // ── Preferences section ─────────────────────────────────
        _animated(const _SectionLabel('НАСТРОЙКИ'), 0.3, 0.65),
        const SizedBox(height: 8),

        _animated(Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), boxShadow: cardShadow(isDark)),
          child: Column(children: [
            _prefRow(
              icon: CupertinoIcons.moon_fill,
              iconBg: const Color(0xFF5856D6),
              title: l.t('dark_mode'),
              sub: l.t('dark_sub'),
              value: themeProv.isDark,
              onChanged: (_) => themeProv.toggle(),
            ),
          ]),
        ), 0.35, 0.75),

        const SizedBox(height: 16),

        // ── Language section ────────────────────────────────────
        _animated(Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), boxShadow: cardShadow(isDark)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFFF9500), borderRadius: BorderRadius.circular(8)),
                child: const Icon(CupertinoIcons.globe, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(l.t('language'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                {'code': 'RU', 'label': 'Русский'},
                {'code': 'KZ', 'label': 'Қазақша'},
                {'code': 'EN', 'label': 'English'},
              ].map((lang) {
                final sel = l.lang == lang['code'];
                return Expanded(child: GestureDetector(
                  onTap: () => l.setLang(lang['code']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: sel ? surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      boxShadow: sel ? softShadow(isDark) : null,
                    ),
                    child: Column(children: [
                      Text(lang['code']!,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: sel ? primary : C.text4)),
                      const SizedBox(height: 1),
                      Text(lang['label']!,
                        style: TextStyle(fontSize: 9, color: sel ? C.text3 : C.text4)),
                    ]),
                  ),
                ));
              }).toList()),
            ),
          ]),
        ), 0.45, 0.82),

        const SizedBox(height: 16),

        // ── Contact developer ───────────────────────────────────
        _animated(
          GestureDetector(
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const ContactScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: cardShadow(isDark),
              ),
              child: Row(children: [
                const TelegramLogo(size: 32),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Связаться с разработчиком',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: adaptiveText1(context))),
                  const SizedBox(height: 1),
                  const Text('Вопросы, ошибки и предложения',
                    style: TextStyle(fontSize: 13, color: C.text4)),
                ])),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
              ]),
            ),
          ),
        0.5, 0.88),

        const SizedBox(height: 16),

        // ── Change password ─────────────────────────────────────
        _animated(
          _actionCard(
            icon: CupertinoIcons.lock_rotation,
            iconBg: primary,
            title: l.t('change_password'),
            sub: l.t('change_password_sub'),
            titleColor: adaptiveText1(context),
            onTap: _openChangePassword,
          ),
        0.5, 0.9),

        const SizedBox(height: 16),

        // ── Logout ──────────────────────────────────────────────
        _animated(
          GestureDetector(
            onTap: () async {
              final ok = await showConfirmDialog(context,
                title: 'Выйти из аккаунта?',
                message: 'Вы будете перенаправлены на экран входа.',
                icon: CupertinoIcons.arrow_right_square,
                danger: true,
                confirmText: 'Выйти',
                cancelText: 'Отмена');
              if (ok == true && mounted) auth.logout();
            },
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
                  decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(CupertinoIcons.arrow_right_square, size: 17, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('logout'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: C.red)),
                  const SizedBox(height: 1),
                  Text(l.t('logout_sub'),
                    style: const TextStyle(fontSize: 13, color: C.text4)),
                ])),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
              ]),
            ),
          ),
        0.55, 0.92),

        const SizedBox(height: 16),

        // ── Delete account (destructive) ────────────────────────
        _animated(
          _actionCard(
            icon: CupertinoIcons.trash,
            iconBg: C.red,
            title: l.t('delete_account'),
            sub: l.t('delete_account_sub'),
            titleColor: C.red,
            onTap: _openDeleteAccount,
          ),
        0.6, 0.95),
      ])),
    );
  }

  // Карточка-действие в стиле блока Logout (иконка + заголовок + подпись + шеврон).
  Widget _actionCard({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String sub,
    required Color titleColor,
    required VoidCallback onTap,
  }) {
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
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: titleColor)),
            const SizedBox(height: 1),
            Text(sub, style: const TextStyle(fontSize: 13, color: C.text4)),
          ])),
          const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
        ]),
      ),
    );
  }

  // ── Смена пароля ──────────────────────────────────────────────
  Future<void> _openChangePassword() async {
    final l = context.read<L10n>();
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (result == true && mounted) showToast(context, l.t('password_changed'));
  }

  // ── Удаление аккаунта ─────────────────────────────────────────
  Future<void> _openDeleteAccount() async {
    final l = context.read<L10n>();
    final auth = context.read<AuthProvider>();
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteAccountSheet(),
    );
    if (password == null || password.isEmpty || !mounted) return;
    final err = await auth.deleteAccount(password);
    if (!mounted) return;
    if (err == null) {
      showToast(context, l.t('account_deleted'));
      // AuthProvider уже очистил токен и user → _AuthGate уведёт на вход.
    } else {
      showToast(context, l.t(err), error: true);
    }
  }

  bool _isCyrillicName(String name) {
    if (name.trim().isEmpty) return true;
    return RegExp(r'^[а-яА-ЯёЁәӘғҒқҚңҢөӨұҰүҮһҺіІ\s\-]+$').hasMatch(name.trim());
  }

  Widget _fieldLabel(String s) => Padding(padding: const EdgeInsets.only(bottom: 7),
    child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: C.text3)));

  Widget _prefRow({
    required IconData icon,
    required Color iconBg,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 17, color: Colors.white),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: adaptiveText1(context))),
          Text(sub, style: const TextStyle(fontSize: 13, color: C.text4)),
        ])),
        CupertinoLiquidSwitch(value: value, onChanged: onChanged, accent: primary),
      ]),
    );
  }

  String _roleLabel(String r, L10n l) =>
    r == 'admin' ? l.t('role_admin') : r == 'teacher' ? l.t('role_teacher') : l.t('role_student');
}

// ── Модалка смены пароля ────────────────────────────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
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
    return _SheetScaffold(
      title: l.t('change_password'),
      icon: CupertinoIcons.lock_rotation,
      accent: primary,
      children: [
        _SheetField(
          label: l.t('current_password'), controller: _current,
          obscure: !_showCurrent, onToggle: () => setState(() => _showCurrent = !_showCurrent),
          onChanged: (_) { if (_error != null) setState(() => _error = null); },
        ),
        const SizedBox(height: 14),
        _SheetField(
          label: l.t('new_password'), controller: _new,
          obscure: !_showNew, onToggle: () => setState(() => _showNew = !_showNew),
          helper: l.t('password_min_8'),
          onChanged: (_) => setState(() { if (_error != null) _error = null; }),
        ),
        if (_error != null) _SheetError(_error!),
        const SizedBox(height: 22),
        _SheetButton(
          label: l.t('change_password'), color: primary,
          enabled: _valid && !_busy, busy: _busy, onTap: _submit,
        ),
      ],
    );
  }
}

// ── Модалка удаления аккаунта ───────────────────────────────────────────────
class _DeleteAccountSheet extends StatefulWidget {
  const _DeleteAccountSheet();
  @override State<_DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<_DeleteAccountSheet> {
  final _pw = TextEditingController();
  bool _showPw = false;

  @override
  void dispose() { _pw.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _SheetScaffold(
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
        _SheetField(
          label: l.t('confirm_password'), controller: _pw,
          obscure: !_showPw, onToggle: () => setState(() => _showPw = !_showPw),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 22),
        _SheetButton(
          label: l.t('delete_account_confirm'), color: C.red,
          enabled: _pw.text.isNotEmpty, busy: false,
          onTap: () => Navigator.of(context).pop(_pw.text),
        ),
      ],
    );
  }
}

// Общий каркас модалки: закруглённый лист, ручка, иконка, заголовок.
class _SheetScaffold extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<Widget> children;
  const _SheetScaffold({required this.title, required this.icon, required this.accent, required this.children});

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
          Center(child: Container(width: 52, height: 52,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, color: accent, size: 24))),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: adaptiveText1(context), letterSpacing: -0.3)),
          const SizedBox(height: 22),
          ...children,
        ]),
      ),
    );
  }
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? helper;
  const _SheetField({required this.label, required this.controller, required this.obscure,
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

class _SheetError extends StatelessWidget {
  final String text;
  const _SheetError(this.text);
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

class _SheetButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled, busy;
  final VoidCallback onTap;
  const _SheetButton({required this.label, required this.color, required this.enabled, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: enabled ? color : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(child: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
          : Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: enabled ? Colors.white : C.text4))),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.text4, letterSpacing: 1.2)),
  );
}
