import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
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
    if (_email.text.trim().isEmpty || _pw.text.isEmpty) {
      setState(() => _error = 'Заполните все поля');
      return;
    }
    setState(() { _error = null; _busy = true; });
    final ok = await context.read<AuthProvider>().login(_email.text.trim(), _pw.text);
    if (!mounted) return;
    // При ok == true _AuthGate сам переключится на MainShell через auth.isAuthenticated
    if (!ok) {
      setState(() { _error = 'Неверный email или пароль'; _busy = false; });
    }
    // Если ok — просто ждём реактивного переключения, _busy сбрасываем на случай задержки
    if (ok) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
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
            Text('Добро пожаловать', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            SizedBox(height: 4),
            Text('Войдите в свой аккаунт', style: TextStyle(fontSize: 14, color: C.text4)),
            SizedBox(height: 28),
            _label('Email'),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(hintText: 'you@example.com'), onSubmitted: (_) => _submit()),
            SizedBox(height: 14),
            _label('Пароль'),
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
                : Text('Войти'))),
            SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Нет аккаунта? ', style: TextStyle(fontSize: 13, color: C.text4)),
              GestureDetector(
                onTap: widget.onGoRegister,
                child: Text('Зарегистрируйтесь', style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600))),
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
