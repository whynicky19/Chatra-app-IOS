import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  final _nameCtrl = TextEditingController();
  late AnimationController _entry;

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
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700,
              color: adaptiveText1(context), letterSpacing: -0.6, height: 1.1)),
          const SizedBox(height: 3),
          Text(l.t('settings_sub'), style: const TextStyle(fontSize: 14, color: C.text4)),
        ])), 0.0, 0.4),

        // ── Profile card ────────────────────────────────────────
        _animated(_SectionLabel('ПРОФИЛЬ'), 0.05, 0.45),
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
              Text(auth.fullName.isNotEmpty ? auth.fullName : auth.email,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
              const SizedBox(height: 2),
              Text(_roleLabel(auth.role, l),
                style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500)),
              // Cyrillic warning
              if (auth.fullName.isNotEmpty && !_isCyrillicName(auth.fullName)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                  ),
                  child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 15, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Ваше ФИО указано не на кириллице. Пожалуйста, обновите его ниже.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w500, height: 1.4),
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
                    decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(CupertinoIcons.xmark_circle, size: 14, color: C.red),
                      SizedBox(width: 7),
                      Expanded(child: Text('ФИО должно быть на кириллице (рус/каз)',
                        style: TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w500))),
                    ]),
                  )),
              const SizedBox(height: 14),
              _fieldLabel(l.t('email')),
              TextField(enabled: false, decoration: InputDecoration(
                hintText: auth.email,
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                  child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)))),
              if (auth.group.isNotEmpty) ...[
                const SizedBox(height: 14),
                _fieldLabel(l.t('group')),
                TextField(enabled: false, decoration: InputDecoration(
                  hintText: auth.group,
                  prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                    child: Icon(CupertinoIcons.person_2, size: 18, color: C.text4)))),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    await auth.updateProfile(_nameCtrl.text.trim());
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.t('saved')), backgroundColor: primary));
                  },
                  child: Text(l.t('save_changes')),
                )),
            ])),
          ]),
        ), 0.1, 0.6),

        const SizedBox(height: 24),

        // ── Preferences section ─────────────────────────────────
        _animated(_SectionLabel('НАСТРОЙКИ'), 0.3, 0.65),
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
                      borderRadius: BorderRadius.circular(9),
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

        // ── Logout ──────────────────────────────────────────────
        _animated(
          GestureDetector(
            onTap: () async {
              final ok = await showCupertinoDialog<bool>(
                context: context,
                builder: (d) => CupertinoAlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  content: const Text('Вы будете перенаправлены на экран входа.'),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Отмена'),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Выйти'),
                    ),
                  ],
                ),
              );
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
        CupertinoSwitch(value: value, onChanged: onChanged, activeTrackColor: primary),
      ]),
    );
  }

  String _roleLabel(String r, L10n l) =>
    r == 'admin' ? l.t('role_admin') : r == 'teacher' ? l.t('role_teacher') : l.t('role_student');
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text4, letterSpacing: 1.2)),
  );
}
