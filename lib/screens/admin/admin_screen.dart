import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
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
  List<dynamic> _posts = [];
  List<dynamic> _aiLogs = [];
  List<dynamic> _aiSummary = [];
  bool _loading = true;
  bool _aiLoading = true;
  bool _classesLoading = true;
  String _search = '';
  int _totalTokens = 0;

  @override void initState() { super.initState(); _tabCtrl = TabController(length: 3, vsync: this); _initAll(); }

  // Загружаем посты (источник названий классов) ДО AI-данных, чтобы _classNameMap был заполнен
  Future<void> _initAll() async { await _load(); await _loadClasses(); await _loadAi(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _users = await context.read<ApiService>().adminUsers(); } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() => _classesLoading = true);
    try { _posts = await context.read<ApiService>().getPosts(); } catch (_) {}
    if (mounted) setState(() => _classesLoading = false);
  }

  // All posts where body has type == 'class'
  List<Map<String, dynamic>> get _allClassPosts {
    return _posts.where((p) {
      try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; }
    }).map((p) {
      try {
        final b = jsonDecode(p['body']) as Map<String, dynamic>;
        return {...p as Map<String, dynamic>, ...b, 'title': p['title']};
      } catch (_) { return p as Map<String, dynamic>; }
    }).toList();
  }

  Future<void> _loadAi() async {
    if (!mounted) return;
    setState(() => _aiLoading = true);
    try {
      final api = context.read<ApiService>();
      _aiSummary = await api.adminAiSummary();
      _aiLogs = await api.adminAiUsage();
      _totalTokens = 0;
      for (final s in _aiSummary) _totalTokens += (s['total_tokens'] as num? ?? 0).toInt();
    } catch (_) {}
    if (mounted) setState(() => _aiLoading = false);
  }

  List<dynamic> get _filtered => _users.where((u) { final q = _search.toLowerCase(); return (u['email'] ?? '').toLowerCase().contains(q) || (u['full_name'] ?? '').toLowerCase().contains(q); }).toList();

  String _fmtTokens(num n) { if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M'; if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K'; return '$n'; }

  // user_id → ФИО (из уже загруженного списка пользователей)
  Map<int, String> get _userNameMap {
    final map = <int, String>{};
    for (final u in _users) {
      final id = (u['id'] as num?)?.toInt();
      if (id == null) continue;
      final name = (u['full_name'] != null && u['full_name'].toString().isNotEmpty)
          ? u['full_name'].toString()
          : u['email']?.toString() ?? 'Пользователь #$id';
      map[id] = name;
    }
    return map;
  }

  // class_id → название класса
  // AI-логи хранят post_id как class_id, поэтому берём из _allClassPosts (посты).
  Map<int, String> get _classNameMap {
    final map = <int, String>{};
    for (final c in _allClassPosts) {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) continue;
      map[id] = c['title']?.toString() ?? 'Класс #$id';
    }
    return map;
  }

  List<Map<String, dynamic>> _perUserSummary() {
    final names = _userNameMap;
    final map = <int, Map<String, dynamic>>{};
    for (final l in _aiLogs) {
      final uid = (l['user_id'] as num?)?.toInt();
      if (uid == null) continue;
      final name = names[uid] ?? 'Пользователь #$uid';
      final tokens = (l['total_tokens'] as num? ?? 0).toInt();
      if (map.containsKey(uid)) {
        map[uid]!['tokens'] = (map[uid]!['tokens'] as int) + tokens;
        map[uid]!['count'] = (map[uid]!['count'] as int) + 1;
      } else {
        map[uid] = {'name': name, 'tokens': tokens, 'count': 1};
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => (b['tokens'] as int).compareTo(a['tokens'] as int));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
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
            Text(l.t('admin'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: C.teal)),
            Text(l.t('admin_sub'), style: TextStyle(fontSize: 12, color: C.text4)),
          ]),
        ])),
        // Stats row
        Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 12), child: Row(children: [
          _stat(Icons.people_rounded, '${_users.length}', l.t('total_label'), C.teal),
          SizedBox(width: 8),
          _stat(Icons.school_rounded, '$teacherCount', l.t('teachers_label'), Color(0xFF6366F1)),
          SizedBox(width: 8),
          _stat(Icons.person_rounded, '$studentCount', l.t('students_label'), Color(0xFF059669)),
        ])),
        // Tabs
        Container(margin: EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)),
          child: TabBar(
            controller: _tabCtrl,
            labelColor: C.teal, unselectedLabelColor: C.text4,
            indicatorColor: C.teal, indicatorSize: TabBarIndicatorSize.label,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            tabs: [Tab(text: l.t('users')), Tab(text: 'AI'), Tab(text: l.t('class_tab'))])),
        SizedBox(height: 8),
        Expanded(child: TabBarView(controller: _tabCtrl, children: [_usersTab(), _aiTab(), _classesTab()])),
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
    final l = context.read<L10n>();
    return Column(children: [
      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: TextField(
        decoration: InputDecoration(hintText: l.t('search_users'), prefixIcon: Icon(Icons.search, size: 18, color: C.text4), contentPadding: EdgeInsets.symmetric(vertical: 10)),
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
                  PopupMenuItem(value: 'student', child: Text(l.t('set_student'))), PopupMenuItem(value: 'teacher', child: Text(l.t('set_teacher'))),
                  PopupMenuItem(value: 'admin', child: Text(l.t('set_admin'))), PopupMenuDivider(),
                  PopupMenuItem(value: u['is_active'] == false ? 'unblock' : 'block', child: Text(u['is_active'] == false ? l.t('unblock') : l.t('block'))),
                  PopupMenuItem(value: 'delete', child: Text(l.t('delete'), style: TextStyle(color: C.red))),
                ]),
              ]));
          }))),
    ]);
  }

  Widget _aiTab() {
    final l = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;

    if (_aiLoading) {
      return Center(child: CircularProgressIndicator(color: C.teal));
    }

    final classNames = _classNameMap;
    final userNames = _userNameMap;
    final userSummary = _perUserSummary();
    final maxUserTokens = userSummary.isNotEmpty ? (userSummary.first['tokens'] as int) : 1;

    return RefreshIndicator(
      color: C.teal,
      onRefresh: _loadAi,
      child: ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 90), children: [
        // Total + refresh
        Container(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [C.teal, C.tealDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: C.teal.withOpacity(0.3), blurRadius: 12, offset: Offset(0, 4))],
          ),
          child: Row(children: [
            Icon(Icons.bolt, size: 20, color: Colors.white),
            SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('total_tokens'), style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600)),
              Text(_fmtTokens(_totalTokens), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
            Spacer(),
            GestureDetector(onTap: _loadAi, child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              child: Row(children: [Icon(Icons.refresh, size: 14, color: Colors.white), SizedBox(width: 4), Text(l.t('refresh'), style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600))]),
            )),
          ])),
        SizedBox(height: 20),

        // ── По классам ──
        if (_aiSummary.isNotEmpty) ...[
          _sectionLabel(l.t('by_classes')),
          SizedBox(height: 8),
          ..._aiSummary.map((s) {
            final cid = (s['class_id'] as num?)?.toInt();
            final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : 'Без класса';
            final tokens = (s['total_tokens'] as num? ?? 0).toInt();
            final reqCount = (s['request_count'] as num? ?? 0).toInt();
            return Container(
              margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.class_rounded, size: 20, color: C.teal)),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(className, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                  SizedBox(height: 2),
                  Text('$reqCount ${l.t('requests_count')}', style: TextStyle(fontSize: 11, color: C.text4)),
                ])),
                SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtTokens(tokens), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: C.teal)),
                  Text('токенов', style: TextStyle(fontSize: 10, color: C.text4)),
                ]),
              ]),
            );
          }),
          SizedBox(height: 20),
        ],

        // ── По пользователям ──
        if (userSummary.isNotEmpty) ...[
          _sectionLabel(l.t('by_users')),
          SizedBox(height: 8),
          ...userSummary.map((u) {
            final name = u['name'] as String;
            final tokens = u['tokens'] as int;
            final count = u['count'] as int;
            final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
            final pct = maxUserTokens > 0 ? tokens / maxUserTokens : 0.0;
            return Container(
              margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Container(width: 42, height: 42,
                  decoration: BoxDecoration(gradient: RadialGradient(colors: [C.teal.withOpacity(0.25), C.teal.withOpacity(0.06)]), shape: BoxShape.circle),
                  child: Center(child: Text(initials, style: TextStyle(color: C.teal, fontWeight: FontWeight.w900, fontSize: 15)))),
                SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis, maxLines: 1),
                  SizedBox(height: 5),
                  ClipRRect(borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), backgroundColor: C.teal.withOpacity(0.08), color: C.teal, minHeight: 4)),
                  SizedBox(height: 3),
                  Text('$count запр.', style: TextStyle(fontSize: 10, color: C.text4)),
                ])),
                SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_fmtTokens(tokens), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: C.teal)),
                  Text('токенов', style: TextStyle(fontSize: 10, color: C.text4)),
                ]),
              ]),
            );
          }),
          SizedBox(height: 20),
        ],

        // ── Детальный лог ──
        if (_aiLogs.isNotEmpty) ...[
          _sectionLabel('${l.t('detail_log')} (${_aiLogs.length})'),
          SizedBox(height: 8),
          Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
              Expanded(flex: 3, child: Text('ПОЛЬЗОВАТЕЛЬ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
              Expanded(flex: 2, child: Text('КЛАСС', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
              SizedBox(width: 60, child: Text('ТОКЕНЫ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4), textAlign: TextAlign.right)),
            ])),
          ...List.generate(_aiLogs.length, (i) {
            final l = _aiLogs[i];
            final uid = (l['user_id'] as num?)?.toInt();
            final cid = (l['class_id'] as num?)?.toInt();
            final userName = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
            final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : '—';
            final isGrade = (l['endpoint'] ?? '').toString().contains('grade');
            final date = l['created_at'] != null
                ? (() { try { final d = DateTime.parse(l['created_at']); return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; } catch (_) { return ''; } })()
                : '';
            return Container(
              margin: EdgeInsets.only(bottom: 4), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                SizedBox(width: 24, child: Text('${i + 1}', style: TextStyle(fontSize: 10, color: C.text4))),
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(userName, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                  Text(date, style: TextStyle(fontSize: 9, color: C.text4)),
                ])),
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(className, style: TextStyle(fontSize: 11, color: C.text4), overflow: TextOverflow.ellipsis),
                  Container(margin: EdgeInsets.only(top: 2), padding: EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: isGrade ? C.teal.withOpacity(0.1) : C.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text(isGrade ? 'Проверка' : 'Чат', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isGrade ? C.teal : C.green))),
                ])),
                SizedBox(width: 60, child: Text('${l['total_tokens'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.teal), textAlign: TextAlign.right)),
              ]),
            );
          }),
        ],

        if (_aiSummary.isEmpty && _aiLogs.isEmpty) Padding(padding: EdgeInsets.all(40), child: Center(child: Column(children: [
          Icon(Icons.bolt, size: 48, color: C.text4), SizedBox(height: 12), Text(l.t('no_ai_data'), style: TextStyle(color: C.text4)),
        ]))),
      ]),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: EdgeInsets.only(bottom: 2),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)));

  // Returns students matching the class group (or all students if no group set)
  List<dynamic> _studentsForClass(String group) {
    final students = _users.where((u) => u['role'] == 'student').toList();
    if (group.isEmpty) return students;
    return students.where((u) => (u['group'] ?? '').toString() == group).toList();
  }

  // ── Classes tab ──
  Widget _classesTab() {
    final l = context.read<L10n>();
    if (_classesLoading) return Center(child: CircularProgressIndicator(color: C.teal));

    final classes = _allClassPosts;
    final userNames = _userNameMap;

    return RefreshIndicator(
      color: C.teal,
      onRefresh: _loadClasses,
      child: classes.isEmpty
          ? ListView(children: [
              SizedBox(height: 120),
              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.class_rounded, size: 48, color: C.text4),
                SizedBox(height: 12),
                Text(l.t('no_classes_admin'), style: TextStyle(color: C.text4, fontSize: 15)),
              ])),
            ])
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: classes.length,
              itemBuilder: (ctx, i) {
                final cls = classes[i];
                final title = cls['title']?.toString() ?? '';
                final coverImg = cls['cover_image'];
                final uid = (cls['user_id'] as num?)?.toInt();
                final creatorName = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
                final description = (cls['description'] ?? '').toString();
                final group = (cls['group'] ?? '').toString();
                final teacherName = (cls['teacher_name'] ?? '').toString();
                final students = _studentsForClass(group);
                final surface = Theme.of(context).colorScheme.surface;

                return GestureDetector(
                  onTap: () => _showStudentsSheet(title, group, students, coverImg, i),
                  child: Container(
                    margin: EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Cover
                      ClipRRect(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                        child: SizedBox(height: 130, width: double.infinity,
                          child: Stack(fit: StackFit.expand, children: [
                            _classCover(coverImg, i),
                            // Students count badge top-right
                            Positioned(top: 10, right: 10, child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.people_rounded, size: 13, color: Colors.white),
                                SizedBox(width: 4),
                                Text('${students.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                              ]),
                            )),
                          ])),
                      ),
                      Padding(padding: EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (description.isNotEmpty) Padding(padding: EdgeInsets.only(top: 3),
                          child: Text(description, style: TextStyle(fontSize: 13, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        SizedBox(height: 10),
                        // Creator row
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(color: C.teal.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            Container(width: 28, height: 28, decoration: BoxDecoration(color: C.teal.withOpacity(0.15), shape: BoxShape.circle),
                              child: Center(child: Text(
                                creatorName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join().isNotEmpty
                                    ? creatorName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join()
                                    : '?',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: C.teal)))),
                            SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.t('created_by'), style: TextStyle(fontSize: 10, color: C.text4, fontWeight: FontWeight.w500)),
                              Text(creatorName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.teal), overflow: TextOverflow.ellipsis),
                            ])),
                            if (group.isNotEmpty) Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                              child: Text(group, style: TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w600))),
                          ]),
                        ),
                        if (teacherName.isNotEmpty) Padding(padding: EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Icon(Icons.person_outline, size: 13, color: C.text4),
                            SizedBox(width: 4),
                            Text(teacherName, style: TextStyle(fontSize: 12, color: C.text4)),
                          ])),
                        SizedBox(height: 10),
                        // Students preview row
                        GestureDetector(
                          onTap: () => _showStudentsSheet(title, group, students, coverImg, i),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: adaptiveSurface2(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: C.teal.withOpacity(0.2)),
                            ),
                            child: Row(children: [
                              // Stacked avatars (up to 3)
                              SizedBox(
                                width: students.isEmpty ? 0 : (students.length == 1 ? 28 : students.length == 2 ? 46 : 64),
                                height: 28,
                                child: Stack(children: [
                                  ...students.take(3).toList().asMap().entries.map((e) {
                                    final s = e.value;
                                    final name = (s['full_name'] ?? s['email'] ?? '').toString();
                                    final initials = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
                                    return Positioned(left: e.key * 18.0, child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(color: C.teal, shape: BoxShape.circle, border: Border.all(color: adaptiveSurface2(context), width: 2)),
                                      child: Center(child: Text(initials, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)))));
                                  }),
                                ]),
                              ),
                              SizedBox(width: students.isEmpty ? 0 : 10),
                              Expanded(child: students.isEmpty
                                ? Text(l.t('no_students_class'), style: TextStyle(fontSize: 13, color: C.text4))
                                : Text(
                                    '${students.length} ${l.t('students_count')}',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: C.teal))),
                              Icon(Icons.arrow_forward_ios, size: 13, color: C.teal),
                            ]),
                          ),
                        ),
                      ])),
                    ]),
                  ),
                );
              }),
    );
  }

  void _showStudentsSheet(String className, String group, List<dynamic> students, dynamic coverImg, int colorIdx) {
    final l = context.read<L10n>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        maxChildSize: 0.92,
        builder: (ctx, sc) => Column(children: [
          // Handle
          Container(width: 40, height: 4, margin: EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
          // Header
          Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 16), child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 52, height: 52, child: _classCover(coverImg, colorIdx))),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(className, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
              SizedBox(height: 2),
              Row(children: [
                Icon(Icons.people_rounded, size: 13, color: C.teal),
                SizedBox(width: 4),
                Text('${students.length} ${l.t('students_count')}',
                  style: TextStyle(fontSize: 12, color: C.teal, fontWeight: FontWeight.w600)),
                if (group.isNotEmpty) ...[
                  SizedBox(width: 8),
                  Container(padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: C.teal.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(group, style: TextStyle(fontSize: 11, color: C.teal, fontWeight: FontWeight.w600))),
                ],
              ]),
            ])),
          ])),
          Divider(height: 1),
          // Student list
          Expanded(child: students.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people_outline, size: 48, color: C.text4),
                SizedBox(height: 12),
                Text(l.t('no_students_class'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text4)),
                if (group.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6),
                  child: Text('Никто из группы "$group" не зарегистрирован', style: TextStyle(fontSize: 13, color: C.text4), textAlign: TextAlign.center)),
              ]))
            : ListView.separated(
                controller: sc,
                padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: students.length,
                separatorBuilder: (_, __) => SizedBox(height: 8),
                itemBuilder: (_, j) {
                  final s = students[j];
                  final name = (s['full_name'] ?? '').toString().trim();
                  final email = (s['email'] ?? '').toString();
                  final sGroup = (s['group'] ?? '').toString();
                  final display = name.isNotEmpty ? name : email.split('@').first;
                  final initials = display.trim().isEmpty ? '?' : display.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
                  return Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Row(children: [
                      Container(width: 44, height: 44,
                        decoration: BoxDecoration(gradient: RadialGradient(colors: [C.teal.withOpacity(0.25), C.teal.withOpacity(0.07)]), shape: BoxShape.circle),
                        child: Center(child: Text(initials, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: C.teal)))),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(display, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text(email, style: TextStyle(fontSize: 12, color: C.text4)),
                      ])),
                      if (sGroup.isNotEmpty) Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                        child: Text(sGroup, style: TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w600))),
                    ]),
                  );
                },
              )),
        ]),
      ),
    );
  }

  Widget _classCover(dynamic coverImg, int index) {
    const grads = [[Color(0xFF006475), Color(0xFF009AAF)], [Color(0xFF0C4A6E), Color(0xFF0369A1)], [Color(0xFF134E4A), Color(0xFF0D9488)], [Color(0xFF312E81), Color(0xFF4338CA)], [Color(0xFF1E3A5F), Color(0xFF2563EB)]];
    final colors = grads[index % grads.length];
    if (coverImg == null) {
      return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)));
    }
    if (coverImg.toString().startsWith('data:')) {
      try {
        return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, width: double.infinity);
      } catch (_) {
        return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors)));
      }
    }
    return Image.network(coverImg, fit: BoxFit.cover, width: double.infinity,
        errorBuilder: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))));
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
      if (mounted) { showToast(context, context.read<L10n>().t('done')); _load(); }
    } catch (_) { if (mounted) showToast(context, context.read<L10n>().t('error'), error: true); }
  }

  void _showCreateDialog() {
    final email = TextEditingController(), pw = TextEditingController(); String role = 'student';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(context.read<L10n>().t('create_user'), style: TextStyle(fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: email, decoration: InputDecoration(hintText: 'Email')), SizedBox(height: 12),
        TextField(controller: pw, obscureText: true, decoration: InputDecoration(hintText: 'Password')), SizedBox(height: 12),
        DropdownButtonFormField<String>(value: role, items: ['student', 'teacher', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(), onChanged: (v) => setS(() => role = v!)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.read<L10n>().t('cancel'))),
        ElevatedButton(onPressed: () async {
          final l = context.read<L10n>();
          try { await context.read<ApiService>().adminCreateUser(email.text.trim(), pw.text, role); Navigator.pop(ctx); showToast(context, l.t('created')); _load(); }
          catch (_) { showToast(context, l.t('error'), error: true); }
        }, child: Text('Create'))],
    )));
  }

  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }
}
