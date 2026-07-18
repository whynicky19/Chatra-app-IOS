import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../providers/org_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ambient_glow.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/toast.dart';

/// Восстановление пароля: шаг 1 — ввод email и запрос кода; шаг 2 — ввод кода
/// и нового пароля. При успехе выполняется авто-вход.
class ForgotPasswordScreen extends StatefulWidget {
  final String orgType;
  final String? initialEmail;
  const ForgotPasswordScreen({super.key, required this.orgType, this.initialEmail});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pw = TextEditingController();
  bool _showPw = false;
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) _email.text = widget.initialEmail!;
  }

  @override
  void dispose() { _email.dispose(); _code.dispose(); _pw.dispose(); super.dispose(); }

  bool get _emailValid => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());

  Future<void> _sendCode() async {
    if (!_emailValid || _busy) return;
    final l = context.read<L10n>();
    setState(() { _busy = true; _error = null; });
    try {
      final devCode = await context.read<AuthProvider>()
          .forgotPassword(_email.text.trim(), orgType: widget.orgType);
      if (!mounted) return;
      setState(() { _codeSent = true; _busy = false; });
      if (devCode.isNotEmpty) _code.text = devCode; // dev-режим
      showToast(context, l.t('code_sent'));
    } catch (_) {
      if (!mounted) return;
      setState(() { _busy = false; _error = l.t('code_send_error'); });
    }
  }

  Future<void> _reset() async {
    if (_busy || _code.text.trim().length < 4 || _pw.text.length < 8) return;
    final l = context.read<L10n>();
    setState(() { _busy = true; _error = null; });
    final err = await context.read<AuthProvider>()
        .resetPassword(_email.text.trim(), _code.text.trim(), _pw.text, orgType: widget.orgType);
    if (!mounted) return;
    if (err == null) {
      showToast(context, l.t('password_reset_success'));
      Navigator.of(context).popUntil((r) => r.isFirst); // авто-вход → MainShell
    } else {
      setState(() { _busy = false; _error = l.t(err); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final org = context.read<OrgProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = org.primaryColor;
    final canReset = _code.text.trim().length >= 4 && _pw.text.length >= 8;

    return Scaffold(
      backgroundColor: isDark ? C.darkBg : C.bg,
      body: Stack(children: [
        AmbientGlow(alignment: Alignment.topRight, color: primary, opacity: isDark ? 0.14 : 0.09),
        AmbientGlow(alignment: Alignment.bottomLeft, color: primary, opacity: isDark ? 0.08 : 0.05),
        SafeArea(child: Stack(children: [
          Positioned(top: 8, left: 16, child: _BackButton(onTap: () => Navigator.of(context).maybePop())),
          Center(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 56),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: SizedBox(width: 84, height: 84, child: Stack(alignment: Alignment.center, children: [
                  Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: primary.withValues(alpha: 0.26), blurRadius: 40, spreadRadius: 8)])),
                  const AppLogo(iconOnly: true, width: 84, height: 84),
                ]))),
                const SizedBox(height: 20),
                Text(_codeSent ? l.t('reset_title') : l.t('forgot_title'), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: adaptiveText1(context))),
                const SizedBox(height: 8),
                Text(_codeSent ? l.t('reset_sub') : l.t('forgot_sub'), textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
                const SizedBox(height: 28),

                if (!_codeSent) ...[
                  _fieldLabel('Email'),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(hintText: 'you@example.com',
                      prefixIcon: Padding(padding: EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.mail, size: 18, color: C.text4))),
                    onChanged: (_) => setState(() { if (_error != null) _error = null; }),
                    onSubmitted: (_) => _sendCode(),
                  ),
                ] else ...[
                  _fieldLabel(l.t('code_from_email')),
                  TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                    onChanged: (_) => setState(() { if (_error != null) _error = null; }),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel(l.t('new_password')),
                  TextField(
                    controller: _pw,
                    obscureText: !_showPw,
                    decoration: InputDecoration(
                      hintText: '••••••••',
                      prefixIcon: const Padding(padding: EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.lock, size: 18, color: C.text4)),
                      suffixIcon: IconButton(
                        icon: Icon(_showPw ? CupertinoIcons.eye_slash : CupertinoIcons.eye, color: C.text4, size: 18),
                        onPressed: () => setState(() => _showPw = !_showPw)),
                    ),
                    onChanged: (_) => setState(() { if (_error != null) _error = null; }),
                  ),
                  Padding(padding: const EdgeInsets.only(top: 6, left: 2),
                    child: Text(l.t('password_min_8'), style: const TextStyle(fontSize: 12, color: C.text4))),
                ],

                if (_error != null) Padding(padding: const EdgeInsets.only(top: 14),
                  child: Container(width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: C.red.withValues(alpha: isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(CupertinoIcons.exclamationmark_circle, color: C.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13, fontWeight: FontWeight.w600))),
                    ]))),
                const SizedBox(height: 24),

                GestureDetector(
                  onTap: _busy ? null : (_codeSent ? _reset : _sendCode),
                  child: AnimatedContainer(duration: const Duration(milliseconds: 200), height: 52,
                    decoration: BoxDecoration(
                      color: (_codeSent ? canReset : _emailValid) || _busy ? primary : adaptiveSurface2(context),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: (_codeSent ? canReset : _emailValid) && !_busy ? primaryGlow(primary, opacity: 0.34) : null),
                    child: Center(child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Text(_codeSent ? l.t('reset_btn') : l.t('send_code'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                            color: (_codeSent ? canReset : _emailValid) ? Colors.white : C.text4)))),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: 16),
                  Center(child: GestureDetector(
                    onTap: _busy ? null : _sendCode,
                    child: Text(l.t('resend_code'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primary)))),
                ],
              ]),
            ),
          )),
        ])),
      ]),
    );
  }

  Widget _fieldLabel(String s) => Padding(padding: const EdgeInsets.only(bottom: 7, left: 2),
    child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.text3)));
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(onTap: onTap, child: Container(width: 38, height: 38,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle, boxShadow: softShadow(isDark)),
      child: Icon(CupertinoIcons.chevron_left, size: 18, color: adaptiveText1(context))));
  }
}
