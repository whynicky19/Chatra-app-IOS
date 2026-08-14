import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cupertino_liquid_switch.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import '../../utils/nav_guard.dart';
import 'about_settings_screen.dart';
import 'ai_limits_screen.dart';
import 'security_settings_screen.dart';
import '../../widgets/wrapping_field.dart';
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
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final primary   = Theme.of(context).colorScheme.primary;

    return Scaffold(
      // bottom: false — тот же edge-to-edge под навбар, что и на остальных
      // вкладках шелла (см. home_screen.dart). Было 100 фиксированных px,
      // рассчитанных В ДОПОЛНЕНИЕ к safe-area инсету, который раньше сама
      // добавляла SafeArea; теперь весь клиренс — в bottomBarClearance().
      body: SafeArea(bottom: false, child: ListView(padding: EdgeInsets.fromLTRB(16, 20, 16, bottomBarClearance(context)), children: [

        _animated(Padding(padding: const EdgeInsets.fromLTRB(4, 0, 4, 26), child: Text(l.t('settings'),
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: adaptiveTextSoft(context)))), 0.0, 0.4),

        // ── Профиль: форма, а не список пунктов, поэтому остаётся карточкой ──
        _animated(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(l.t('profile').toUpperCase(), style: _captionStyle(context)),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: groupSeparator(context), width: hairline(context)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: _fieldLabel(l.t('full_name'))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                  child: Text(_roleLabel(auth.role, l),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: primary)),
                ),
              ]),
              const SizedBox(height: 7),
              WrappingField(
                controller: _nameCtrl,
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  prefixIcon: Padding(padding: EdgeInsets.only(left: 4),
                    child: Icon(CupertinoIcons.person, size: 18, color: C.text4)))),
              if (_nameCtrl.text.isNotEmpty && !_isValidName(_nameCtrl.text))
                Padding(padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: C.red.withValues(alpha: isDark ? 0.16 : 0.08),
                      borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Row(children: [
                      const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 15, color: C.red),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l.t('name_letters_only'),
                        style: const TextStyle(fontSize: 14, color: C.red, fontWeight: FontWeight.w500, letterSpacing: -0.2))),
                    ]),
                  )),
              const SizedBox(height: 16),
              _fieldLabel(l.t('email')),
              const SizedBox(height: 7),
              TextField(enabled: false, decoration: InputDecoration(
                hintText: auth.email,
                prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                  child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)))),
              // Кнопка появляется только когда есть что сохранять.
              if (_nameCtrl.text.trim().isNotEmpty && _nameCtrl.text.trim() != auth.fullName.trim()) ...[
                const SizedBox(height: 18),
                Tappable(
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
                      // Плоская акцентная кнопка без цветного свечения — как
                      // «Готово» в системных формах.
                      color: primary,
                      borderRadius: BorderRadius.circular(AppRadii.button),
                    ),
                    child: Center(child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CupertinoActivityIndicator(radius: 9, color: Colors.white))
                      : Text(l.t('save_changes'),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: Colors.white))),
                  ),
                ),
              ],
            ]),
          ),
        ]), 0.1, 0.6),

        const SizedBox(height: 26),

        // ── Предпочтения: тема и язык одной группой ──
        _animated(SettingsGroup(
          caption: l.t('preferences'),
          children: [
            SettingsRow(
              pos: GroupPos.middle,
              icon: CupertinoIcons.moon_fill,
              iconBg: const Color(0xFF5856D6),
              title: l.t('dark_mode'),
              sub: l.t('dark_sub'),
              trailing: CupertinoLiquidSwitch(
                value: themeProv.isDark,
                onChanged: (_) => themeProv.toggle(),
                accent: primary,
              ),
            ),
            SettingsRow(
              pos: GroupPos.last,
              icon: CupertinoIcons.globe,
              iconBg: const Color(0xFFFF9500),
              title: l.t('language'),
              value: _langLabel(l.lang),
              onTap: () => _showLanguagePicker(context, l),
            ),
          ],
        ), 0.3, 0.75),

        const SizedBox(height: 26),

        // ── Разделы ──
        _animated(SettingsGroup(
          caption: l.t('sections'),
          children: [
            SettingsRow(
              pos: GroupPos.middle,
              icon: CupertinoIcons.shield_lefthalf_fill,
              iconBg: primary,
              title: l.t('security_section'),
              sub: l.t('security_section_sub'),
              onTap: () => guardedPush(context,
                MaterialPageRoute(builder: (_) => const SecuritySettingsScreen())),
            ),
            SettingsRow(
              pos: GroupPos.middle,
              icon: CupertinoIcons.sparkles,
              iconBg: primary,
              title: l.t('ai_limit_section'),
              sub: l.t('ai_limit_section_sub'),
              onTap: () => guardedPush(context,
                MaterialPageRoute(builder: (_) => const AiLimitsScreen())),
            ),
            SettingsRow(
              pos: GroupPos.last,
              icon: CupertinoIcons.info_circle_fill,
              iconBg: primary,
              title: l.t('about_section'),
              sub: l.t('about_section_sub'),
              onTap: () => guardedPush(context,
                MaterialPageRoute(builder: (_) => const AboutSettingsScreen())),
            ),
          ],
        ), 0.45, 0.85),

        const SizedBox(height: 26),

        // ── Выход: своя группа (действие, а не настройка) ──
        _animated(SettingsGroup(children: [
          SettingsRow(
            pos: GroupPos.last,
            icon: CupertinoIcons.arrow_right_square,
            iconBg: C.red,
            title: l.t('logout'),
            sub: l.t('logout_sub'),
            titleColor: C.red,
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
          ),
        ]), 0.55, 0.92),
      ])),
    );
  }

  TextStyle _captionStyle(BuildContext context) => TextStyle(
    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: adaptiveText3(context));

  /// Любые буквы Unicode, пробел, дефис, апостроф — без цифр и спецсимволов.
  ///
  /// Здесь была та же кириллица-only проверка, что и на экране регистрации:
  /// пользователь с латинским именем не мог сохранить профиль.
  bool _isValidName(String name) {
    final n = name.trim();
    if (n.isEmpty) return true;
    return RegExp(r"^[\p{L}\p{M}\s\-']+$", unicode: true).hasMatch(n);
  }

  Widget _fieldLabel(String s) => Text(s,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: adaptiveText3(context)));

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
        // Выбор одного из нескольких — сгруппированный список с галочкой у
        // выбранного (как языки в системных настройках), а не набор
        // самостоятельных плашек с рамками.
        InsetGroup(children: [
          for (var i = 0; i < _options.length; i++)
            _LanguageOptionRow(
              label: _options[i]['label']!,
              selected: l.lang == _options[i]['code'],
              primary: primary,
              isDark: isDark,
              pos: innerPos(i, _options.length),
              onTap: () { l.setLang(_options[i]['code']!); Navigator.pop(context); },
            ),
        ]),
      ],
    );
  }
}

class _LanguageOptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;
  final bool isDark;
  final GroupPos pos;
  final VoidCallback onTap;
  const _LanguageOptionRow({
    required this.label, required this.selected, required this.primary,
    required this.isDark, required this.pos, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GroupRow(
    pos: pos,
    color: Colors.transparent,
    separatorInset: 16,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    onTap: onTap,
    child: Row(children: [
      Expanded(child: Text(label,
        // Выбор несёт цвет и галочка, а не вес.
        style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w500,
          color: selected ? primary : adaptiveTextSoft(context)))),
      if (selected) Icon(CupertinoIcons.checkmark_alt, size: 20, color: primary),
    ]),
  );
}
