import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminState();
}

class _AdminState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _users = [];
  List<dynamic> _aiLogs = [];
  List<dynamic> _aiSummary = [];
  bool _loading = true;
  String _search = '';
  int _totalTokens = 0;

  @override void initState() { super.initState(); _tabCtrl = TabController(length: 2, vsync: this); _load(); _loadAi(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _users = await context.read<ApiService>().adminUsers(); } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadAi() async {
    try {
      _aiSummary = await context.read<ApiService>().adminAiSummary();
      _aiLogs = await context.read<ApiService>().adminAiUsage();
      _totalTokens = 0;
      for (final s in _aiSummary) _totalTokens += (s['total_tokens'] as num? ?? 0).toInt();
      setState(() {});
    } catch (_) {}
  }

  List<dynamic> get _filtered => _users.where((u) { final q = _search.toLowerCase(); return (u['email'] ?? '').toLowerCase().contains(q) || (u['full_name'] ?? '').toLowerCase().contains(q); }).toList();

  String _fmtTokens(num n) { if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M'; if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K'; return '$n'; }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final teacherCount = _users.where((u) => u['role'] == 'teacher').length;
    final studentCount = _users.where((u) => u['role'] == 'student').length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 16), child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(gradient: LinearGradient(colors: [C.teal, C.tealDk]), borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.35), blurRadius: 10, offset: Offset(0, 4))]),
            child: Icon(Icons.shield_rounded, color: Colors.white, size: 22)),
          SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Панель Админа', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.teal)),
            Text('Управление пользователями', style: TextStyle(fontSize: 12, color: C.text4)),
          ]),
        ])),
        // Stats row
        Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: Row(children: [
          _stat(Icons.people_rounded, '${_users.length}', 'Всего', C.teal),
          SizedBox(width: 8),
          _stat(Icons.school_rounded, '$teacherCount', 'Учителей', Color(0xFF6366F1)),
          SizedBox(width: 8),
          _stat(Icons.person_rounded, '$studentCount', 'Студентов', Color(0xFF059669)),
        ])),
        // Tabs
        Container(margin: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: C.teal, unselectedLabelColor: C.text4,
            indicatorColor: C.teal, indicatorSize: TabBarIndicatorSize.label,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [Tab(text: 'Пользователи'), Tab(text: 'AI Использование')])),
        SizedBox(height: 8),
        Expanded(child: TabBarView(controller: _tabCtrl, children: [_usersTab(), _aiTab()])),
      ])),
      floatingActionButton: Padding(padding: EdgeInsets.only(bottom: 76),
        child: FloatingActionButton(
          backgroundColor: C.teal,
          child: Icon(Icons.person_add_rounded, color: Colors.white),
          onPressed: _showCreateDialog,
        )),
    );
  }

  Widget _stat(IconData ic, String val, String label, Color color) => Expanded(child: Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(ic, size: 16, color: color)),
      SizedBox(height: 8),
      Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      Text(label, style: TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w500)),
    ])));

  Widget _usersTab() {
    return Column(children: [
      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: TextField(
        decoration: InputDecoration(hintText: 'Search users...', prefixIcon: Icon(Icons.search, size: 18, color: C.text4), contentPadding: EdgeInsets.symmetric(vertical: 10)),
        onChanged: (v) => setState(() => _search = v))),
      SizedBox(height: 8),
      Expanded(child: _loading ? Center(child: CircularProgressIndicator(color: C.teal)) :
        RefreshIndicator(color: C.teal, onRefresh: _load, child: ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 90), itemCount: _filtered.length, itemBuilder: (ctx, i) {
            final u = _filtered[i];
            final name = u['full_name'] ?? u['email']?.split('@').first ?? '';
            return AnimatedContainer(duration: Duration(milliseconds: 200), margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(gradient: RadialGradient(colors: [C.teal.withOpacity(0.25), C.teal.withOpacity(0.08)]), shape: BoxShape.circle),
                  child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: TextStyle(color: C.teal, fontWeight: FontWeight.w900, fontSize: 17)))),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)), SizedBox(height: 2),
                  Text(u['email'] ?? '', style: TextStyle(fontSize: 12, color: C.text4)),
                ])),
                Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: u['role'] == 'admin' ? C.teal.withOpacity(0.12) : u['role'] == 'teacher' ? Color(0xFF6366F1).withOpacity(0.1) : adaptiveSurface2(context),
                    borderRadius: BorderRadius.circular(20)),
                  child: Text(u['role'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                    color: u['role'] == 'admin' ? C.teal : u['role'] == 'teacher' ? Color(0xFF6366F1) : C.text4))),
                PopupMenuButton<String>(icon: Icon(Icons.more_vert, size: 20, color: C.text4), onSelected: (v) => _action(u, v), itemBuilder: (_) => [
                  PopupMenuItem(value: 'student', child: Text('Set Student')), PopupMenuItem(value: 'teacher', child: Text('Set Teacher')),
                  PopupMenuItem(value: 'admin', child: Text('Set Admin')), PopupMenuDivider(),
                  PopupMenuItem(value: u['is_active'] == false ? 'unblock' : 'block', child: Text(u['is_active'] == false ? 'Unblock' : 'Block')),
                  PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: C.red))),
                ]),
              ]));
          }))),
    ]);
  }

  Widget _aiTab() {
    final surface = Theme.of(context).colorScheme.surface;
    final fill = adaptiveSurface2(context);
    return ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
      // Per-class summary cards (horizontal scroll)
      if (_aiSummary.isNotEmpty) ...[
        SizedBox(height: 72, child: ListView(scrollDirection: Axis.horizontal, children: _aiSummary.map((s) => Container(
          width: 150, margin: EdgeInsets.only(right: 8), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.teal.withOpacity(0.2))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [Icon(Icons.bolt, size: 11, color: C.teal), SizedBox(width: 3),
              Flexible(child: Text(s['class_name'] ?? (s['class_id'] != null ? '#${s['class_id']}' : 'Общий'), style: TextStyle(fontSize: 9, color: C.teal, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis))]),
            Text(_fmtTokens(s['total_tokens'] ?? 0), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            Text('${s['request_count'] ?? 0} запр.', style: TextStyle(fontSize: 9, color: C.text4)),
          ]),
        )).toList())),
        SizedBox(height: 12),
      ],
      // Total + refresh
      Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(Icons.bolt, size: 16, color: C.teal), SizedBox(width: 8),
          Text('Итого: ', style: TextStyle(fontSize: 13, color: C.text4)),
          Text('${_fmtTokens(_totalTokens)} токенов', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: C.teal)),
          Spacer(),
          GestureDetector(onTap: _loadAi, child: Row(children: [Icon(Icons.refresh, size: 16, color: C.text4), SizedBox(width: 4), Text('Обновить', style: TextStyle(fontSize: 12, color: C.text4))])),
        ])),
      SizedBox(height: 16),
      // Detailed log table
      if (_aiLogs.isNotEmpty) ...[
        // Table header
        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
            Expanded(flex: 3, child: Text('ПОЛЬЗОВАТЕЛЬ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
            Expanded(flex: 2, child: Text('ТИП', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
            SizedBox(width: 60, child: Text('ТОКЕНЫ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4), textAlign: TextAlign.right)),
          ])),
        // Table rows
        ...List.generate(_aiLogs.length > 30 ? 30 : _aiLogs.length, (i) {
          final l = _aiLogs[i];
          final isGrade = (l['type'] ?? '').toString().contains('grade') || (l['type'] ?? '').toString().contains('check');
          return Container(
            margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(fontSize: 11, color: C.text4))),
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l['user_name'] ?? l['user_email'] ?? '#${l['user_id']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(l['created_at'] ?? '', style: TextStyle(fontSize: 9, color: C.text4)),
              ])),
              Expanded(flex: 2, child: Row(children: [
                Container(padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: isGrade ? C.teal.withOpacity(0.1) : C.green.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(isGrade ? 'Проверка' : 'Чат', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isGrade ? C.teal : C.green))),
              ])),
              SizedBox(width: 60, child: Text('${l['total_tokens'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.teal), textAlign: TextAlign.right)),
            ]),
          );
        }),
      ],
      if (_aiSummary.isEmpty && _aiLogs.isEmpty) Padding(padding: EdgeInsets.all(40), child: Center(child: Column(children: [
        Icon(Icons.bolt, size: 48, color: C.text4), SizedBox(height: 12), Text('No AI usage data', style: TextStyle(color: C.text4)),
      ]))),
    ]);
  }

  void _action(dynamic u, String action) async {
    final api = context.read<ApiService>();
    if (u['id'] == context.read<AuthProvider>().userId && ['block', 'delete'].contains(action)) return;
    try {
      switch (action) {
        case 'student': case 'teacher': case 'admin': await api.adminSetRole(u['id'], action); break;
        case 'block': await api.adminBlock(u['id']); break;
        case 'unblock': await api.adminUnblock(u['id']); break;
        case 'delete': await api.adminDelete(u['id']); break;
      }
      if (mounted) { showToast(context, 'Done'); _load(); }
    } catch (_) { if (mounted) showToast(context, 'Error', error: true); }
  }

  void _showCreateDialog() {
    final email = TextEditingController(), pw = TextEditingController(); String role = 'student';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Create User', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: email, decoration: InputDecoration(hintText: 'Email')), SizedBox(height: 12),
        TextField(controller: pw, obscureText: true, decoration: InputDecoration(hintText: 'Password')), SizedBox(height: 12),
        DropdownButtonFormField<String>(value: role, items: ['student', 'teacher', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(), onChanged: (v) => setS(() => role = v!)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel')),
        ElevatedButton(onPressed: () async {
          try { await context.read<ApiService>().adminCreateUser(email.text.trim(), pw.text, role); Navigator.pop(ctx); showToast(context, 'Created'); _load(); }
          catch (_) { showToast(context, 'Error', error: true); }
        }, child: Text('Create'))],
    )));
  }

  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }
}
