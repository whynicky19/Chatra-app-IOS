import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/org_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;
  const RegisterScreen({super.key, this.onGoLogin});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _name   = TextEditingController();
  final _email  = TextEditingController();
  final _pw     = TextEditingController();
  final _groupQ = TextEditingController();
  String _group = '';
  List<String> _suggestions = [];
  bool _showSugg = false;
  bool _submitted = false;
  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim  = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override void dispose() { _anim.dispose(); super.dispose(); }

  bool get _nameIsCyrillic {
    final n = _name.text.trim();
    if (n.isEmpty) return true;
    return RegExp(r'^[а-яА-ЯёЁәӘғҒқҚңҢөӨұҰүҮһҺіІ\s\-]+$').hasMatch(n);
  }

  bool _isValid({required bool isSchool}) {
    final parts = _name.text.trim().split(' ').where((s) => s.isNotEmpty).toList();
    return parts.length >= 2 &&
        _nameIsCyrillic &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) &&
        _pw.text.length >= 6 &&
        _pwScore > 40 &&
        (isSchool || _group.isNotEmpty);
  }

  int get _pwScore {
    final p = _pw.text; if (p.isEmpty) return 0; int s = 0;
    if (p.length >= 6)  s += 20;
    if (p.length >= 10) s += 20;
    if (RegExp(r'[A-Z]').hasMatch(p)) s += 20;
    if (RegExp(r'[0-9]').hasMatch(p)) s += 20;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s += 20;
    return s;
  }

  void _searchGroups(String q) async {
    if (q.trim().isEmpty) { setState(() { _suggestions = []; _showSugg = false; }); return; }
    try {
      final r = await context.read<ApiService>().searchGroups(q);
      if (mounted) setState(() { _suggestions = r; _showSugg = r.isNotEmpty; });
    } catch (_) {}
  }

  Future<void> _submit() async {
    final org = context.read<OrgProvider>();
    if (!_isValid(isSchool: org.isSchool) || _submitted) return;
    setState(() => _submitted = true);
    final auth = context.read<AuthProvider>();
    final goLogin = widget.onGoLogin;
    final ok = await auth.register(_email.text.trim(), _pw.text, 'student',
        fullName: _name.text.trim(),
        group: org.isSchool ? null : (_group.isEmpty ? null : _group),
        orgType: org.orgTypeString);
    if (!mounted) {
      if (ok) goLogin?.call();
      return;
    }
    if (ok) {
      showToast(context, context.read<L10n>().t('account_created'));
      goLogin?.call();
    } else {
      setState(() => _submitted = false);
      final l = context.read<L10n>();
      showToast(context, auth.lastError ?? l.t('error_generic'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l        = context.watch<L10n>();
    final auth     = context.watch<AuthProvider>();
    final org      = context.watch<OrgProvider>();
    final isSchool = org.isSchool;
    final sc       = _pwScore;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      body: Stack(children: [
        Container(decoration: BoxDecoration(gradient: LinearGradient(
          colors: isDark
              ? [org.primaryColor.withOpacity(0.12), org.primaryColor.withOpacity(0.22)]
              : org.gradientColors,
          begin: Alignment.topRight, end: Alignment.bottomLeft,
        ))),
        Positioned(top: -60, left: -50, child: _Blob(size: 240, opacity: 0.07)),
        Positioned(bottom: -80, right: -60, child: _Blob(size: 300, opacity: 0.06)),

        // Кнопка назад → выбор организации
        Positioned(
          top: 8, left: 8,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 20),
              onPressed: () => context.read<OrgProvider>().clear(),
            ),
          ),
        ),

        SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: FadeTransition(opacity: _fade, child: SlideTransition(position: _slide,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 48, offset: const Offset(0, 20)),
                  BoxShadow(color: org.primaryColor.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Icon
                Container(width: 64, height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: org.gradientColors),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: tealGlow(opacity: 0.28),
                  ),
                  child: const Icon(Icons.person_add_rounded, color: Colors.white, size: 30)),
                const SizedBox(height: 16),
                Text(l.t('register'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: adaptiveText1(context), letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text(l.t('register_sub'), style: const TextStyle(fontSize: 14, color: C.text4)),
                const SizedBox(height: 28),

                // Full name
                _fieldLabel(l.t('full_name_label')),
                TextField(
                  controller: _name,
                  decoration: InputDecoration(
                    hintText: 'Иванов Иван Иванович',
                    prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.person_outline_rounded, size: 18, color: C.text4)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                // Подсказка: нужно минимум 2 слова
                if (_name.text.isNotEmpty &&
                    _name.text.trim().split(' ').where((s) => s.isNotEmpty).length < 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                        SizedBox(width: 7),
                        Expanded(child: Text('Введите фамилию и имя полностью', style: TextStyle(fontSize: 12, color: Color(0xFFB45309), fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  ),
                // Предупреждение если ФИО не на кириллице
                if (_name.text.isNotEmpty &&
                    _name.text.trim().split(' ').where((s) => s.isNotEmpty).length >= 2 &&
                    !_nameIsCyrillic)
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

                // Email
                _fieldLabel('Email'),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.mail_outline_rounded, size: 18, color: C.text4)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 14),

                // Group — только для университета
                if (!isSchool) ...[
                  _fieldLabel(l.t('group_label')),
                  TextField(
                    controller: _groupQ,
                    decoration: InputDecoration(
                      hintText: 'ISU-25',
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                        child: Icon(Icons.group_outlined, size: 18, color: C.text4)),
                      suffixIcon: _group.isNotEmpty
                          ? const Icon(Icons.check_circle_rounded, color: C.green, size: 20)
                          : null,
                    ),
                    onChanged: (v) { _group = ''; _searchGroups(v); setState(() {}); },
                  ),
                  if (_showSugg) Container(
                    margin: const EdgeInsets.only(top: 4),
                    constraints: const BoxConstraints(maxHeight: 150),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: softShadow(isDark),
                    ),
                    child: ListView(shrinkWrap: true, children: _suggestions.map((g) => ListTile(
                      dense: true,
                      title: Text(g, style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () => setState(() { _group = g; _groupQ.text = g; _showSugg = false; }),
                    )).toList())),
                  const SizedBox(height: 14),
                ],

                // Password
                _fieldLabel(l.t('password_label')),
                TextField(
                  controller: _pw,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock_outline_rounded, size: 18, color: C.text4)),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_pw.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: sc / 100,
                          backgroundColor: adaptiveSurface2(context),
                          color: sc <= 40 ? C.red : sc <= 60 ? C.yellow : C.green,
                          minHeight: 4,
                        ),
                      )),
                      const SizedBox(width: 10),
                      Text(
                        sc <= 40 ? l.t('password_weak') : sc <= 60 ? l.t('password_medium') : l.t('password_strong'),
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: sc <= 40 ? C.red : sc <= 60 ? C.yellow : C.green,
                        ),
                      ),
                    ]),
                    if (sc <= 40 && _pw.text.length >= 6)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            const Icon(Icons.error_outline_rounded, size: 14, color: C.red),
                            const SizedBox(width: 7),
                            Expanded(child: Text(
                              l.lang == 'KZ'
                                  ? 'Құпия сөз тым қарапайым. Бас әріп, сан немесе арнайы таңба қосыңыз'
                                  : l.lang == 'EN'
                                      ? 'Password is too weak. Add uppercase letters, numbers or symbols'
                                      : 'Пароль слишком слабый. Добавьте заглавные буквы, цифры или символы',
                              style: const TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w500),
                            )),
                          ]),
                        ),
                      ),
                  ])),

                const SizedBox(height: 26),

                SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: auth.isLoading || !_isValid(isSchool: isSchool) || _submitted ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: org.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: auth.isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l.t('register_btn'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  )),

                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${l.t('has_account')} ', style: const TextStyle(fontSize: 13, color: C.text4)),
                  GestureDetector(
                    onTap: widget.onGoLogin,
                    child: Text(l.t('login_link'), style: const TextStyle(
                        fontSize: 13, color: C.teal, fontWeight: FontWeight.w700))),
                ]),
              ]),
            ),
          )),
        ))),
      ]),
    );
  }

  Widget _fieldLabel(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 0.3))));
}

class _Blob extends StatelessWidget {
  final double size;
  final double opacity;
  const _Blob({required this.size, required this.opacity});
  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
  );
}
