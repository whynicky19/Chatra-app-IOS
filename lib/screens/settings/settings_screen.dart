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
  bool _notif = true, _aiInsights = true;
  late AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = context.read<AuthProvider>().fullName;
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() { _entry.dispose(); _nameCtrl.dispose(); super.dispose(); }

  Widget _animated(Widget child, double start, double end) {
    final anim = CurvedAnimation(parent: _entry, curve: Interval(start, end, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth       = context.watch<AuthProvider>();
    final themeProv  = context.watch<ThemeProvider>();
    final l          = context.watch<L10n>();
    final surface    = Theme.of(context).colorScheme.surface;
    final isDark     = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 90), children: [

        // ── Page title ────────────────────────────────────────
        _animated(Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.t('settings'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: C.teal, letterSpacing: -0.8, height: 1.1)),
          const SizedBox(height: 2),
          Text(l.t('settings_sub'), style: const TextStyle(fontSize: 13, color: C.text4)),
        ])), 0.0, 0.45),

        // ── Section: Profile ──────────────────────────────────
        _animated(_SectionLabel('ПРОФИЛЬ'), 0.05, 0.5),
        const SizedBox(height: 10),

        // Profile card with gradient banner
        _animated(Container(
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), boxShadow: cardShadow(isDark)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            // Gradient banner
            Stack(clipBehavior: Clip.none, children: [
              Container(height: 76, decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF006475), C.teal], begin: Alignment.topLeft, end: Alignment.bottomRight),
              )),
              Positioned(bottom: -36, left: 20, child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [C.teal, Color(0xFF006475)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: Border.all(color: surface, width: 3),
                  boxShadow: tealGlow(opacity: 0.30),
                ),
                child: Center(child: Text(auth.initials, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900))),
              )),
            ]),
            const SizedBox(height: 48),
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(auth.fullName.isNotEmpty ? auth.fullName : auth.email, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
              const SizedBox(height: 2),
              Text(_roleLabel(auth.role, l), style: const TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600)),
              // Предупреждение если ФИО не на кириллице
              if (auth.fullName.isNotEmpty && !_isCyrillicName(auth.fullName)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFBBF24).withOpacity(0.5)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFD97706)),
                    const SizedBox(width: 8),
                    const Expanded(child: Text(
                      'Ваше ФИО указано не на кириллице. Пожалуйста, обновите его ниже.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w500, height: 1.4),
                    )),
                  ]),
                ),
              ],
              const SizedBox(height: 18),
              _label(l.t('full_name')),
              TextField(controller: _nameCtrl, onChanged: (_) => setState(() {}), decoration: const InputDecoration(
                prefixIcon: Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.person_outline, size: 18, color: C.text4)))),
              // Ошибка валидации ФИО
              if (_nameCtrl.text.isNotEmpty && !_isCyrillicName(_nameCtrl.text))
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.error_outline_rounded, size: 14, color: C.red),
                      SizedBox(width: 7),
                      Expanded(child: Text('ФИО должно быть на кириллице (рус/каз)', style: TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                ),
              const SizedBox(height: 14),
              _label(l.t('email')),
              TextField(enabled: false, decoration: InputDecoration(
                hintText: auth.email,
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.mail_outline, size: 18, color: C.text4)))),
              if (auth.group.isNotEmpty) ...[
                const SizedBox(height: 14),
                _label(l.t('group')),
                TextField(enabled: false, decoration: InputDecoration(
                  hintText: auth.group,
                  prefixIcon: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.group_outlined, size: 18, color: C.text4)))),
              ],
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                onPressed: () async {
                  await auth.updateProfile(_nameCtrl.text.trim());
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.t('saved')), backgroundColor: C.teal));
                },
                child: Text(l.t('save_changes')),
              )),
            ])),
          ]),
        ), 0.1, 0.65),

        const SizedBox(height: 24),

        // ── Section: Preferences ─────────────────────────────
        _animated(_SectionLabel('НАСТРОЙКИ'), 0.3, 0.7),
        const SizedBox(height: 10),

        _animated(Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), boxShadow: cardShadow(isDark)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _prefRow(Icons.dark_mode_outlined, l.t('dark_mode'), l.t('dark_sub'), themeProv.isDark, (_) => themeProv.toggle()),
            _divider(),
            _prefRow(Icons.notifications_outlined, l.t('notif'), l.t('notif_sub'), _notif, (v) => setState(() => _notif = v)),
            _divider(),
            _prefRow(Icons.auto_awesome_outlined, l.t('ai_insights'), l.t('ai_sub'), _aiInsights, (v) => setState(() => _aiInsights = v)),
          ]),
        ), 0.35, 0.78),

        const SizedBox(height: 16),

        // Language
        _animated(Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), boxShadow: cardShadow(isDark)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('language'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                {'code': 'RU', 'label': 'Русский'},
                {'code': 'KZ', 'label': 'Қазақша'},
                {'code': 'EN', 'label': 'English'},
              ].map((lang) {
                final sel = l.lang == lang['code'];
                return Expanded(child: GestureDetector(
                  onTap: () => l.setLang(lang['code']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: sel ? C.teal : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: sel ? tealGlow(opacity: 0.22) : null,
                    ),
                    child: Column(children: [
                      Text(lang['code']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? Colors.white : C.text4)),
                      const SizedBox(height: 2),
                      Text(lang['label']!, style: TextStyle(fontSize: 9, color: sel ? Colors.white70 : C.text4)),
                    ]),
                  ),
                ));
              }).toList()),
            ),
          ]),
        ), 0.45, 0.85),

        const SizedBox(height: 16),

        // ── Logout ────────────────────────────────────────────
        _animated(GestureDetector(
          onTap: () => auth.logout(),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: C.red.withOpacity(0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: C.red.withOpacity(0.12)),
            ),
            child: Row(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: C.red.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.logout_rounded, color: C.red, size: 22)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('logout'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.red)),
                const SizedBox(height: 2),
                Text(l.t('logout_sub'), style: const TextStyle(fontSize: 12, color: C.text4)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: C.red, size: 22),
            ]),
          ),
        ), 0.55, 0.95),
      ])),
    );
  }

  bool _isCyrillicName(String name) {
    if (name.trim().isEmpty) return true;
    return RegExp(r'^[а-яА-ЯёЁәӘғҒқҚңҢөӨұҰүҮһҺіІ\s\-]+$').hasMatch(name.trim());
  }

  Widget _label(String s) => Padding(padding: const EdgeInsets.only(bottom: 7),
    child: Text(s, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.8)));

  Widget _divider() => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
    child: Divider(height: 16, color: C.border.withOpacity(0.5)));

  Widget _prefRow(IconData icon, String title, String sub, bool val, Function(bool) onChanged) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Container(width: 40, height: 40,
        decoration: BoxDecoration(color: C.teal.withOpacity(0.10), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 19, color: C.teal)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
        Text(sub, style: const TextStyle(fontSize: 12, color: C.text4)),
      ])),
      Switch(value: val, onChanged: onChanged, activeColor: C.teal, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ]),
  );

  String _roleLabel(String r, L10n l) => r == 'admin' ? l.t('role_admin') : r == 'teacher' ? l.t('role_teacher') : l.t('role_student');
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.text4, letterSpacing: 1.2)),
  );
}
