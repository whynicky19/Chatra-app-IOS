import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback? onGoLogin;
  const RegisterScreen({super.key, this.onGoLogin});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _groupQ = TextEditingController();
  String _group = '';
  List<String> _suggestions = [];
  bool _showSugg = false;
  bool _submitted = false;

  bool get _ok {
    final parts = _name.text.trim().split(' ').where((s) => s.isNotEmpty).toList();
    return parts.length >= 2 &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim()) &&
        _pw.text.length >= 6 &&
        _group.isNotEmpty;
  }

  int get _pwScore {
    final p = _pw.text; if (p.isEmpty) return 0; int s = 0;
    if (p.length >= 6) s += 20; if (p.length >= 10) s += 20;
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
    if (!_ok || _submitted) return;
    _submitted = true;
    final auth = context.read<AuthProvider>();
    final ok = await auth.register(_email.text.trim(), _pw.text, 'student',
        fullName: _name.text.trim(), group: _group);
    if (!mounted) return;
    if (ok) {
      showToast(context, context.read<L10n>().t('account_created'));
      await Future.delayed(Duration(milliseconds: 1200));
      if (!mounted) return;
      widget.onGoLogin?.call();
    } else {
      _submitted = false;
      final l = context.read<L10n>();
      showToast(context, auth.lastError ?? l.t('error_generic'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final auth = context.watch<AuthProvider>();
    final sc = _pwScore;
    final surface = Theme.of(context).colorScheme.surface;
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(maxWidth: 420), padding: EdgeInsets.all(28),
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(24)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 60, height: 60,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(colors: [C.teal, C.tealDk])),
            child: Icon(Icons.person_add_rounded, color: Colors.white, size: 30)),
          SizedBox(height: 16),
          Text(l.t('register'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text(l.t('register_sub'), style: TextStyle(fontSize: 14, color: C.text4)),
          SizedBox(height: 24),
          _label(l.t('full_name_label')),
          TextField(controller: _name, decoration: InputDecoration(hintText: 'Иванов Иван'), onChanged: (_) => setState(() {})),
          SizedBox(height: 14),
          _label('Email'),
          TextField(controller: _email, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(hintText: 'you@example.com'), onChanged: (_) => setState(() {})),
          SizedBox(height: 14),
          _label(l.t('group_label')),
          TextField(controller: _groupQ,
            decoration: InputDecoration(
              suffixIcon: _group.isNotEmpty ? Icon(Icons.check_circle, color: C.green, size: 20) : null),
            onChanged: (v) { _group = ''; _searchGroups(v); setState(() {}); }),
          if (_showSugg) Container(
            margin: EdgeInsets.only(top: 4), constraints: BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
            child: ListView(shrinkWrap: true, children: _suggestions.map((g) => ListTile(
              dense: true, title: Text(g),
              onTap: () => setState(() { _group = g; _groupQ.text = g; _showSugg = false; }))).toList())),
          SizedBox(height: 14),
          _label(l.t('password_label')),
          TextField(controller: _pw, obscureText: true,
            onChanged: (_) => setState(() {})),
          if (_pw.text.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Row(children: [
            Expanded(flex: 2, child: ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: sc / 100, backgroundColor: C.surface2,
                color: sc <= 40 ? C.red : sc <= 60 ? C.yellow : C.green, minHeight: 3))),
            SizedBox(width: 8),
            Text(sc <= 40 ? l.t('password_weak') : sc <= 60 ? l.t('password_medium') : l.t('password_strong'),
              style: TextStyle(fontSize: 11, color: C.text4)),
          ])),
          SizedBox(height: 24),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
            onPressed: auth.isLoading || !_ok || _submitted ? null : _submit,
            child: auth.isLoading
              ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l.t('register_btn')))),
          SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${l.t('has_account')} ', style: TextStyle(fontSize: 13, color: C.text4)),
            GestureDetector(
              onTap: widget.onGoLogin,
              child: Text(l.t('login_link'), style: TextStyle(fontSize: 13, color: C.teal, fontWeight: FontWeight.w600))),
          ]),
        ]),
      ),
    ))));
  }

  Widget _label(String s) => Padding(padding: EdgeInsets.only(bottom: 6),
    child: Align(alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.text3))));
}
