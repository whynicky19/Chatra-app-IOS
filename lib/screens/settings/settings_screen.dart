import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cupertino_liquid_switch.dart';
import '../../widgets/toast.dart';
import 'about_settings_screen.dart';
import 'ai_limits_screen.dart';
import 'security_settings_screen.dart';
import 'settings_shared.dart';

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

        _animated(Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('settings'),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
              color: adaptiveText1(context), letterSpacing: -0.4, height: 1.1)),
          const SizedBox(height: 3),
          Text(l.t('settings_sub'), style: const TextStyle(fontSize: 14, color: C.text4)),
        ])), 0.0, 0.4),

        _animated(_SectionLabel(l.t('profile').toUpperCase()), 0.05, 0.45),
        const SizedBox(height: 8),

        _animated(Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), boxShadow: cardShadow(isDark)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _fieldLabel(l.t('full_name'))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.card)),
                  child: Text(_roleLabel(auth.role, l),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: primary)),
                ),
              ]),
              const SizedBox(height: 7),
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
                    child: Row(children: [
                      const Icon(CupertinoIcons.xmark_circle, size: 14, color: C.red),
                      const SizedBox(width: 7),
                      Expanded(child: Text(l.t('name_cyrillic_only'),
                        style: const TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w600))),
                    ]),
                  )),
              const SizedBox(height: 14),
              _fieldLabel(l.t('email')),
              TextField(enabled: false, decoration: InputDecoration(
                hintText: auth.email,
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                  child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)))),
              if (_nameCtrl.text.trim().isNotEmpty && _nameCtrl.text.trim() != auth.fullName.trim()) ...[
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
              ],
            ])),
          ]),
        ), 0.1, 0.6),

        const SizedBox(height: 24),

        _animated(_SectionLabel(l.t('preferences').toUpperCase()), 0.3, 0.65),
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

        _animated(GestureDetector(
          onTap: () => _showLanguagePicker(context, l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), boxShadow: cardShadow(isDark)),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFFF9500), borderRadius: BorderRadius.circular(8)),
                child: const Icon(CupertinoIcons.globe, size: 17, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(child: Text(l.t('language'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: adaptiveText1(context)))),
              Text(_langLabel(l.lang), style: const TextStyle(fontSize: 15, color: C.text4)),
              const SizedBox(width: 6),
              const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
            ]),
          ),
        ), 0.45, 0.82),

        const SizedBox(height: 16),

        _animated(_SectionLabel(l.t('sections').toUpperCase()), 0.46, 0.84),
        const SizedBox(height: 10),

        _animated(
          SettingsActionCard(
            icon: CupertinoIcons.shield_lefthalf_fill,
            iconBg: primary,
            title: l.t('security_section'),
            sub: l.t('security_section_sub'),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SecuritySettingsScreen())),
          ),
        0.48, 0.88),

        const SizedBox(height: 16),

        _animated(
          SettingsActionCard(
            icon: CupertinoIcons.sparkles,
            iconBg: primary,
            title: l.t('ai_limit_section'),
            sub: l.t('ai_limit_section_sub'),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AiLimitsScreen())),
          ),
        0.49, 0.89),

        const SizedBox(height: 16),

        _animated(
          SettingsActionCard(
            icon: CupertinoIcons.info_circle_fill,
            iconBg: primary,
            title: l.t('about_section'),
            sub: l.t('about_section_sub'),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AboutSettingsScreen())),
          ),
        0.5, 0.9),

        const SizedBox(height: 16),

        _animated(
          GestureDetector(
            onTap: () async {
              final ok = await showConfirmDialog(context,
                title: '${l.t('logout')}?',
                message: l.t('logout_confirm_msg'),
                icon: CupertinoIcons.arrow_right_square,
                danger: true,
                confirmText: l.t('sign_out'),
                cancelText: l.t('cancel'));
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
      ])),
    );
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

  static const _langOptions = [
    {'code': 'RU', 'label': 'Русский'},
    {'code': 'KZ', 'label': 'Қазақша'},
    {'code': 'EN', 'label': 'English'},
  ];

  String _langLabel(String? code) =>
    _langOptions.firstWhere((o) => o['code'] == code, orElse: () => _langOptions.first)['label']!;

  void _showLanguagePicker(BuildContext context, L10n l) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LanguageSheet(),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet();

  static const _options = [
    {'code': 'RU', 'label': 'Русский'},
    {'code': 'KZ', 'label': 'Қазақша'},
    {'code': 'EN', 'label': 'English'},
  ];

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SheetScaffold(
      title: l.t('language'),
      accent: const Color(0xFFFF9500),
      children: [
        for (final lang in _options) ...[
          _LanguageOptionRow(
            label: lang['label']!,
            selected: l.lang == lang['code'],
            primary: primary,
            isDark: isDark,
            onTap: () { l.setLang(lang['code']!); Navigator.pop(context); },
          ),
          if (lang != _options.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;
  final bool isDark;
  final VoidCallback onTap;
  const _LanguageOptionRow({
    required this.label, required this.selected, required this.primary,
    required this.isDark, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? primary.withValues(alpha: isDark ? 0.16 : 0.08) : adaptiveSurface2(context),
        borderRadius: BorderRadius.circular(14),
        border: selected ? Border.all(color: primary.withValues(alpha: 0.4)) : null,
      ),
      child: Row(children: [
        Expanded(child: Text(label,
          style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : adaptiveText1(context)))),
        if (selected) Icon(CupertinoIcons.check_mark_circled_solid, size: 20, color: primary),
      ]),
    ),
  );
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
