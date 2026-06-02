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

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _showPw = false;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = l.t('fill_fields'));
      return;
    }
    setState(() { _error = null; _busy = true; });
    final ok = await context.read<AuthProvider>().login(_email.text.trim(), _pw.text);
    if (!mounted) return;
    if (!ok) setState(() { _error = l.t('wrong_creds'); _busy = false; });
    if (ok) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(
      body: SafeArea(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
        child: Container(
          constraints: BoxConstraints(maxWidth: 420),
          padding: EdgeInsets.all(28),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/logo.png', width: 180, height: 180),
            SizedBox(height: 20),
            Text(l.t('welcome'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text(l.t('login_sub'), style: TextStyle(fontSize: 14, color: C.text4)),
            SizedBox(height: 28),
            _label('Email'),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: 'you@example.com'), onSubmitted: (_) => _submit()),
            SizedBox(height: 14),
            _label(l.t('password')),
            TextField(controller: _pw, obscureText: !_showPw,
              decoration: InputDecoration(hintText: '••••••••',
                suffixIcon: IconButton(icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility, color: C.text4, size: 20),
                  onPressed: () => setState(() => _showPw = !_showPw))),
              onSubmitted: (_) => _submit()),
            if (_error != null) Padding(padding: EdgeInsets.only(top: 10), child: Container(
              width: double.infinity, padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: C.redLt, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [Icon(Icons.error_outline, color: C.red, size: 16), SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: C.red, fontSize: 13)))]))),
            SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l.t('login')))),
            SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${l.t('no_account')} ', style: TextStyle(fontSize: 13, color: C.text4)),
              GestureDetector(
                onTap: widget.onGoRegister,
                child: Text(l.t('register_link'), style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600))),
            ]),
          ]),
        ),
      )),
    );
  }

  Widget _label(String s) => Padding(padding: EdgeInsets.only(bottom: 6),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.text3))));
}
