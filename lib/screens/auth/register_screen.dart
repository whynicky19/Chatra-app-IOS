import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/org_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/toast.dart';
import '../legal/privacy_policy_screen.dart';
import '../legal/terms_screen.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;
  const RegisterScreen({super.key, this.onGoLogin});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name   = TextEditingController();
  final _email  = TextEditingController();
  final _pw     = TextEditingController();
  bool _showPw = false;
  bool _submitted = false;
  bool _agreedTerms = false;

  @override
  void dispose() { _name.dispose(); _email.dispose(); _pw.dispose(); super.dispose(); }

  /// Проверяем не алфавит, а осмысленность: любые буквы Unicode, пробел, дефис,
  /// апостроф — без цифр и спецсимволов.
  ///
  /// Раньше здесь стояло требование «только кириллица». Это блокировало
  /// регистрацию любому пользователю с латинским именем — в том числе ревьюеру
  /// App Store, который вводит «John Smith» и получает заблокированную кнопку
  /// (отклонение по Guideline 2.1 «не удалось завершить регистрацию»).
  /// Заодно отсекалась казахская латиница.
  bool get _nameIsValid {
    final n = _name.text.trim();
    if (n.isEmpty) return true;
    return RegExp(r"^[\p{L}\p{M}\s\-']+$", unicode: true).hasMatch(n);
  }

  bool get _isValid {
    final parts = _name.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    return parts.length >= 2 &&
        _nameIsValid &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) &&
        _pw.text.length >= 8 &&
        _pwScore > 40 &&
        _agreedTerms;
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

  Future<void> _submit() async {
    final org = context.read<OrgProvider>();
    if (!_isValid || _submitted) return;
    setState(() => _submitted = true);
    final auth = context.read<AuthProvider>();
    final email = _email.text.trim();
    final orgType = org.orgTypeString;
    final ok = await auth.register(email, _pw.text, 'student',
        fullName: _name.text.trim(),
        orgType: orgType);
    if (!mounted) return;
    if (ok) {
      showToast(context,
          context.read<L10n>().t(
              auth.lastRegisterEmailSent ? 'account_created' : 'code_send_error'),
          error: !auth.lastRegisterEmailSent);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        VerifyEmailScreen(email: email, orgType: orgType, autoSend: false)));
      setState(() => _submitted = false);
    } else {
      setState(() => _submitted = false);
      final l = context.read<L10n>();
      showToast(context, l.t(auth.lastError ?? 'register_error'), error: true);
    }
  }

  Widget _reveal(int step, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 420 + step * 110),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c)),
      child: child,
    );
  }

  Widget _hint(String text, {bool error = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = error ? C.red : C.amberDk;
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (error ? C.red : C.amber).withValues(alpha: isDark ? 0.16 : 0.09),
          borderRadius: BorderRadius.circular(AppRadii.chip),
        ),
        child: Row(children: [
          Icon(error ? CupertinoIcons.exclamationmark_circle : CupertinoIcons.info_circle, size: 14, color: color),
          const SizedBox(width: 7),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l       = context.watch<L10n>();
    final auth    = context.watch<AuthProvider>();
    final org     = context.watch<OrgProvider>();
    final sc      = _pwScore;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = org.primaryColor;
    final canSubmit = !auth.isLoading && _isValid && !_submitted;

    final nameWords = _name.text.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;

    return Scaffold(
      backgroundColor: isDark ? C.darkBg : C.bg,
      body: Stack(children: [
        SafeArea(child: Stack(children: [
          Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _reveal(0, const Center(child: AppLogo(iconOnly: true, width: 84, height: 84))),
                const SizedBox(height: 20),

                _reveal(1, Column(children: [
                  Text(l.t('register'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: adaptiveText1(context))),
                  const SizedBox(height: 8),
                  Text(l.t('register_sub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
                ])),
                const SizedBox(height: 28),

                _reveal(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel(l.t('full_name_label')),
                  TextField(
                    controller: _name,
                    autofillHints: const [AutofillHints.name],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: l.t('fio_placeholder'),
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.person, size: 18, color: C.text4)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_name.text.isNotEmpty && nameWords < 2)
                    _hint(l.t('enter_full_name')),
                  if (_name.text.isNotEmpty && nameWords >= 2 && !_nameIsValid)
                    _hint(l.t('name_letters_only'), error: true),
                  const SizedBox(height: 14),

                  _fieldLabel('Email'),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'you@example.com',
                      prefixIcon: Padding(padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel(l.t('password_label')),
                  TextField(
                    controller: _pw,
                    obscureText: !_showPw,
                    autocorrect: false,
                    enableSuggestions: false,
                    // newPassword — чтобы менеджер паролей предложил
                    // сгенерировать надёжный, а не подставил существующий.
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.lock, size: 18, color: C.text4)),
                      suffixIcon: IconButton(
                        icon: Icon(_showPw ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                            color: C.text4, size: 18),
                        onPressed: () => setState(() => _showPw = !_showPw),
                      ),
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
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: sc <= 40 ? C.red : sc <= 60 ? C.yellow : C.green,
                          ),
                        ),
                      ]),
                      if (sc <= 40 && _pw.text.length >= 6)
                        _hint(
                          l.lang == 'KZ'
                              ? 'Құпия сөз тым қарапайым. Бас әріп, сан немесе арнайы таңба қосыңыз'
                              : l.lang == 'EN'
                                  ? 'Password is too weak. Add uppercase letters, numbers or symbols'
                                  : 'Пароль слишком слабый. Добавьте заглавные буквы, цифры или символы',
                          error: true,
                        ),
                    ])),
                ])),
                const SizedBox(height: 20),

                _reveal(3, Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  GestureDetector(
                    onTap: () => setState(() => _agreedTerms = !_agreedTerms),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: _agreedTerms ? primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: _agreedTerms ? primary : C.text4.withValues(alpha: 0.5),
                          width: 1.6),
                      ),
                      child: _agreedTerms
                          ? const Icon(CupertinoIcons.checkmark_alt, size: 15, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Политика конфиденциальности обязана быть доступна В МОМЕНТ
                  // сбора данных, а не только в настройках после входа —
                  // Apple 5.1.1(i) и требования GDPR об информировании.
                  Expanded(child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    GestureDetector(
                      onTap: () => setState(() => _agreedTerms = !_agreedTerms),
                      child: Text('${l.t('terms_agree')} · ',
                        style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TermsScreen())),
                      child: Text(l.t('terms_view'),
                        style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w700)),
                    ),
                    const Text(' · ', style: TextStyle(fontSize: 13, color: C.text4)),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                      child: Text(l.t('pp_title'),
                        style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w700)),
                    ),
                  ])),
                ])),
                const SizedBox(height: 18),

                _reveal(3, Column(children: [
                  GestureDetector(
                    onTap: canSubmit ? _submit : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: canSubmit || auth.isLoading ? primary : adaptiveSurface2(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Align(heightFactor: 1, child: auth.isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Text(l.t('register_btn'), style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1,
                            color: canSubmit ? Colors.white : C.text4))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${l.t('has_account')} ', style: const TextStyle(fontSize: 13.5, color: C.text4)),
                    GestureDetector(
                      onTap: widget.onGoLogin,
                      child: Text(l.t('login_link'), style: TextStyle(
                          fontSize: 13.5, color: primary, fontWeight: FontWeight.w700))),
                  ]),
                ])),
              ]),
            ),
          )),
        ])),
      ]),
    );
  }

  Widget _fieldLabel(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 7, left: 2),
    child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text3)));
}
