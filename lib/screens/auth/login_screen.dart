import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/org_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/tappable.dart';
import 'verify_email_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onGoRegister;
  const LoginScreen({super.key, this.onGoRegister});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _showPw = false;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reason = context.read<AuthProvider>().consumeSessionEndReason();
      if (reason != null) setState(() => _error = context.read<L10n>().t(reason));
    });
  }

  @override
  void dispose() { _email.dispose(); _pw.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = l.t('fill_fields')); return;
    }
    setState(() { _error = null; _busy = true; });
    final orgType = context.read<OrgProvider>().orgTypeString;
    final errKey = await context.read<AuthProvider>().login(_email.text.trim(), _pw.text, orgType: orgType);
    if (!mounted) return;
    setState(() => _busy = false);
    if (errKey == 'email_not_verified') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
        VerifyEmailScreen(email: _email.text.trim(), orgType: orgType, autoSend: true)));
      return;
    }
    if (errKey != null) setState(() => _error = l.t(errKey));
  }

  void _openForgot() {
    final orgType = context.read<OrgProvider>().orgTypeString;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
      ForgotPasswordScreen(orgType: orgType, initialEmail: _email.text.trim().isEmpty ? null : _email.text.trim())));
  }

  Widget _reveal(int step, Widget child) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 220 + step * 45),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: c)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l       = context.watch<L10n>();
    final org     = context.read<OrgProvider>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = org.primaryColor;

    return Scaffold(
      backgroundColor: isDark ? C.darkBg : C.bg,
      body: Stack(children: [
        SafeArea(child: Stack(children: [
          Positioned(top: 8, left: 16, child: _BackButton(onTap: () => context.read<OrgProvider>().clear())),

          Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AutofillGroup(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _reveal(0, const Center(child: AppLogo(width: 104, height: 104))),
                const SizedBox(height: 24),

                _reveal(1, Column(children: [
                  Text(l.t('welcome'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: adaptiveText1(context))),
                  const SizedBox(height: 8),
                  Text(l.t('login_sub'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
                ])),
                const SizedBox(height: 32),

                _reveal(2, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Email'),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    // autofillHints включают менеджеры паролей и системное
                    // автозаполнение iOS/Android — без них вход приходится
                    // набирать руками.
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'you@example.com',
                      prefixIcon: Padding(padding: EdgeInsets.only(left: 4),
                        child: Icon(CupertinoIcons.mail, size: 18, color: C.text4)),
                    ),
                    onChanged: (_) { if (_error != null) setState(() => _error = null); },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 14),

                  _fieldLabel(l.t('password')),
                  TextField(
                    controller: _pw,
                    obscureText: !_showPw,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
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
                    onChanged: (_) { if (_error != null) setState(() => _error = null); },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Tappable(
                      onTap: _openForgot,
                      child: Text(l.t('forgot_password_link'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
                    ),
                  ),
                ])),

                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: _error == null ? const SizedBox(width: double.infinity) : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: C.red.withValues(alpha: isDark ? 0.16 : 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        const Icon(CupertinoIcons.exclamationmark_circle, color: C.red, size: 16),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error ?? '', style: const TextStyle(color: C.red, fontSize: 13, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                _reveal(3, Column(children: [
                  Tappable(
                    onTap: _busy ? null : _submit,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      constraints: const BoxConstraints(minHeight: 52),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Align(heightFactor: 1, child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                        : Text(l.t('login'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.1))),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${l.t('no_account')} ', style: const TextStyle(fontSize: 13, color: C.text4)),
                    Tappable(
                      onTap: widget.onGoRegister,
                      child: Text(l.t('register_link'), style: TextStyle(
                          fontSize: 13, color: primary, fontWeight: FontWeight.w700))),
                  ]),
                ])),
              ])),
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

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tappable(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: softShadow(isDark),
        ),
        child: Icon(CupertinoIcons.chevron_left, size: 18, color: adaptiveText1(context)),
      ),
    );
  }
}
