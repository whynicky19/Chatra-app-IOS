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

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameCtrl = TextEditingController();
  bool _notif = true, _aiInsights = true;

  @override
  void initState() { super.initState(); _nameCtrl.text = context.read<AuthProvider>().fullName; }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final themeProv = context.watch<ThemeProvider>();
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final fill = adaptiveSurface2(context);
    final text1 = adaptiveText1(context);

    return Scaffold(
      body: SafeArea(child: ListView(padding: EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
        Text(l.t('settings'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: C.teal)),
        SizedBox(height: 4),
        Text(l.t('settings_sub'), style: TextStyle(fontSize: 14, color: C.text4)),
        SizedBox(height: 24),

        // Profile card
        Container(padding: EdgeInsets.all(24), decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22)),
          child: Column(children: [
            CircleAvatar(radius: 44, backgroundColor: C.teal, child: Text(auth.initials, style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800))),
            SizedBox(height: 12),
            Text(l.t('academic_profile'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text1)),
            Text(_roleLabel(auth.role, l), style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w500)),
            SizedBox(height: 20),
            _label(l.t('full_name')),
            TextField(controller: _nameCtrl, decoration: InputDecoration(prefixIcon: Icon(Icons.person_outline, size: 18, color: C.teal))),
            SizedBox(height: 14),
            _label(l.t('email')),
            TextField(enabled: false, decoration: InputDecoration(hintText: auth.email, prefixIcon: Icon(Icons.mail_outline, size: 18, color: C.teal))),
            SizedBox(height: 14),
            if (auth.group.isNotEmpty) ...[
              _label(l.t('group')),
              TextField(enabled: false, decoration: InputDecoration(hintText: auth.group, prefixIcon: Icon(Icons.group_outlined, size: 18, color: C.teal))),
              SizedBox(height: 14),
            ],
            SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: () async {
              await auth.updateProfile(_nameCtrl.text.trim());
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.t('saved')), backgroundColor: C.teal));
            }, child: Text(l.t('save_changes')))),
          ])),
        SizedBox(height: 16),

        // Preferences
        Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('preferences'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text1)),
            SizedBox(height: 16),
            _prefRow(Icons.dark_mode_outlined, l.t('dark_mode'), l.t('dark_sub'), themeProv.isDark, (_) => themeProv.toggle()),
            SizedBox(height: 10),
            _prefRow(Icons.notifications_outlined, l.t('notif'), l.t('notif_sub'), _notif, (v) => setState(() => _notif = v)),
            SizedBox(height: 10),
            _prefRow(Icons.auto_awesome_outlined, l.t('ai_insights'), l.t('ai_sub'), _aiInsights, (v) => setState(() => _aiInsights = v)),
            SizedBox(height: 14),
            // Language
            Text(l.t('language'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text1)),
            SizedBox(height: 8),
            Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                {'code': 'RU', 'label': 'Русский', 'flag': '🇷🇺'},
                {'code': 'KZ', 'label': 'Қазақша', 'flag': '🇰🇿'},
                {'code': 'EN', 'label': 'English', 'flag': '🇬🇧'},
              ].map((lang) {
                final sel = l.lang == lang['code'];
                return Expanded(child: GestureDetector(
                  onTap: () => l.setLang(lang['code']!),
                  child: AnimatedContainer(duration: Duration(milliseconds: 200), padding: EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: sel ? C.teal : Colors.transparent, borderRadius: BorderRadius.circular(12),
                      boxShadow: sel ? [BoxShadow(color: C.teal.withOpacity(0.3), blurRadius: 8)] : null),
                    child: Column(children: [
                      Text(lang['code']!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? Colors.white : C.text4)),
                      SizedBox(height: 2),
                      Text(lang['label']!, style: TextStyle(fontSize: 9, color: sel ? Colors.white70 : C.text4)),
                    ]))));
              }).toList())),
          ])),
        SizedBox(height: 16),

        // Logout
        Container(padding: EdgeInsets.all(18), decoration: BoxDecoration(color: C.red.withOpacity(0.06), borderRadius: BorderRadius.circular(22)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: C.red.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.logout, color: C.red, size: 22)),
            SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('logout'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.red)),
              SizedBox(height: 2),
              Text(l.t('logout_sub'), style: TextStyle(fontSize: 12, color: C.text4)),
            ])),
            IconButton(icon: Icon(Icons.chevron_right, color: C.red), onPressed: () => auth.logout()),
          ])),
      ])),
    );
  }

  Widget _label(String s) => Padding(padding: EdgeInsets.only(bottom: 6), child: Text(s, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)));

  Widget _prefRow(IconData icon, String title, String sub, bool val, Function(bool) onChanged) => Container(
    padding: EdgeInsets.all(14), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: C.teal.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: C.teal)),
      SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
        Text(sub, style: TextStyle(fontSize: 11, color: C.text4)),
      ])),
      Switch(value: val, onChanged: onChanged, activeColor: C.teal),
    ]));

  String _roleLabel(String r, L10n l) => r == 'admin' ? l.t('role_admin') : r == 'teacher' ? l.t('role_teacher') : l.t('role_student');
}
