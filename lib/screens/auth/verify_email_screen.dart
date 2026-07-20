import 'dart:async';
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

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  final String orgType;
  final bool autoSend;
  const VerifyEmailScreen({super.key, required this.email, required this.orgType, this.autoSend = false});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoSend) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _resend(initial: true));
    }
  }

  @override
  void dispose() { _timer?.cancel(); _code.dispose(); super.dispose(); }

  void _startCooldown() {
    _cooldown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend({bool initial = false}) async {
    if (_cooldown > 0) return;
    final auth = context.read<AuthProvider>();
    final l = context.read<L10n>();
    try {
      final res = await auth.resendVerification(widget.email, orgType: widget.orgType);
      if (!mounted) return;
      _startCooldown();
      if (res != null && res.devCode.isNotEmpty) _code.text = res.devCode;
      if (res != null && !res.sent) {
        showToast(context, l.t('code_send_error'), error: true);
      } else if (!initial) {
        showToast(context, l.t('code_sent'));
      }
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      showToast(context, l.t('code_send_error'), error: true);
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length < 4 || _busy) return;
    final l = context.read<L10n>();
    setState(() { _busy = true; _error = null; });
    final err = await context.read<AuthProvider>()
        .verifyEmail(widget.email, _code.text.trim(), orgType: widget.orgType);
    if (!mounted) return;
    if (err == null) {
      showToast(context, l.t('email_verified'));
      Navigator.of(context).popUntil((r) => r.isFirst);
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

    return Scaffold(
      backgroundColor: isDark ? C.darkBg : C.bg,
      body: Stack(children: [
        AmbientGlow(alignment: Alignment.topLeft, color: primary, opacity: isDark ? 0.14 : 0.09),
        AmbientGlow(alignment: Alignment.bottomRight, color: primary, opacity: isDark ? 0.08 : 0.05),
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
                Text(l.t('verify_email'), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15, color: adaptiveText1(context))),
                const SizedBox(height: 8),
                Text(l.t('verify_email_sub'), textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: C.text4, height: 1.4)),
                const SizedBox(height: 6),
                Text('${l.t('sent_to')} ${widget.email}', textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 28),

                _fieldLabel(l.t('code_from_email')),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 10),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                  onChanged: (_) { if (_error != null) setState(() => _error = null); },
                  onSubmitted: (_) => _verify(),
                ),

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
                  onTap: _busy ? null : _verify,
                  child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(16),
                      boxShadow: _busy ? null : primaryGlow(primary, opacity: 0.34)),
                    child: Align(heightFactor: 1, child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : Text(l.t('verify_btn'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
                ),
                const SizedBox(height: 18),
                Center(child: GestureDetector(
                  onTap: _cooldown > 0 ? null : () => _resend(),
                  child: Text(
                    _cooldown > 0 ? '${l.t('resend_in')} $_cooldown${l.lang == 'EN' ? 's' : 'с'}' : l.t('resend_code'),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      color: _cooldown > 0 ? C.text4 : primary)),
                )),
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
