import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onGoRegister;
  const LoginScreen({super.key, this.onGoRegister});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _pw    = TextEditingController();
  bool _showPw = false;
  String? _error;
  bool _busy = false;
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

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = l.t('fill_fields')); return;
    }
    setState(() { _error = null; _busy = true; });
    final ok = await context.read<AuthProvider>().login(_email.text.trim(), _pw.text);
    if (!mounted) return;
    if (!ok) setState(() { _error = l.t('wrong_creds'); _busy = false; });
    else setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l       = context.watch<L10n>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;

    return Scaffold(
      body: Stack(children: [
        // ── Gradient background ──────────────────────────────
        Container(decoration: BoxDecoration(gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF051215), const Color(0xFF082028)]
              : [const Color(0xFF006475), const Color(0xFF009AAF)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ))),
        // Decorative blobs
        Positioned(top: -80, right: -60, child: _Blob(size: 260, opacity: 0.07)),
        Positioned(bottom: -100, left: -70, child: _Blob(size: 320, opacity: 0.06)),
        Positioned(top: 160, left: -40, child: _Blob(size: 180, opacity: 0.05)),

        // ── Card content ──────────────────────────────────────
        SafeArea(child: Center(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: FadeTransition(opacity: _fade, child: SlideTransition(position: _slide,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 48, offset: const Offset(0, 20)),
                  BoxShadow(color: C.teal.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Logo
                Image.asset('assets/logo.png', width: 96, height: 96),
                const SizedBox(height: 20),
                Text(l.t('welcome'), style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900,
                  color: adaptiveText1(context), letterSpacing: -0.5,
                )),
                const SizedBox(height: 4),
                Text(l.t('login_sub'), style: const TextStyle(fontSize: 14, color: C.text4)),
                const SizedBox(height: 32),

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
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 14),

                // Password
                _fieldLabel(l.t('password')),
                TextField(
                  controller: _pw,
                  obscureText: !_showPw,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.lock_outline_rounded, size: 18, color: C.text4)),
                    suffixIcon: IconButton(
                      icon: Icon(_showPw ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          color: C.text4, size: 18),
                      onPressed: () => setState(() => _showPw = !_showPw),
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),

                // Error
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: C.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: const TextStyle(color: C.red, fontSize: 13, fontWeight: FontWeight.w500))),
                    ]),
                  )),

                const SizedBox(height: 24),

                // Button
                SizedBox(width: double.infinity, height: 52,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: C.teal,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l.t('login'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  )),

                const SizedBox(height: 22),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('${l.t('no_account')} ', style: const TextStyle(fontSize: 13, color: C.text4)),
                  GestureDetector(
                    onTap: widget.onGoRegister,
                    child: Text(l.t('register_link'), style: const TextStyle(
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
