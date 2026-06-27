import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminState();
}

class _AdminState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _users   = [];
  List<dynamic> _posts   = [];
  List<dynamic> _aiLogs  = [];
  List<dynamic> _aiSummary = [];
  Map<int, List<dynamic>> _classMembers = {};
  bool _loading       = true;
  bool _aiLoading     = true;
  bool _classesLoading = true;
  String _search      = '';
  int _totalTokens    = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _initAll();
  }

  @override void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _initAll() async { await _load(); await _loadClasses(); await _loadAi(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _users = await context.read<ApiService>().adminUsers(); } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() => _classesLoading = true);
    final api = context.read<ApiService>();
    try { _posts = await api.getPosts(); } catch (_) {}
    // Fetch real members for each class in parallel
    final classes = _allClassPosts;
    final results = await Future.wait(classes.map((c) async {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) return MapEntry(0, <dynamic>[]);
      try {
        final members = await api.getClassMembers(id);
        return MapEntry(id, members);
      } catch (_) {
        return MapEntry(id, <dynamic>[]);
      }
    }));
    _classMembers = Map.fromEntries(results.where((e) => e.key != 0));
    if (mounted) setState(() => _classesLoading = false);
  }

  List<Map<String, dynamic>> get _allClassPosts {
    return _posts.where((p) {
      try { return jsonDecode(p['body'])['type'] == 'class'; } catch (_) { return false; }
    }).map((p) {
      try { final b = jsonDecode(p['body']) as Map<String, dynamic>; return {...p as Map<String, dynamic>, ...b, 'title': p['title']}; }
      catch (_) { return p as Map<String, dynamic>; }
    }).toList();
  }

  Future<void> _loadAi() async {
    if (!mounted) return;
    setState(() => _aiLoading = true);
    try {
      final api = context.read<ApiService>();
      _aiSummary = await api.adminAiSummary();
      _aiLogs    = await api.adminAiUsage();
      _totalTokens = 0;
      for (final s in _aiSummary) _totalTokens += (s['total_tokens'] as num? ?? 0).toInt();
    } catch (_) {}
    if (mounted) setState(() => _aiLoading = false);
  }

  List<dynamic> get _filtered => _users.where((u) {
    final q = _search.toLowerCase();
    return (u['email'] ?? '').toLowerCase().contains(q) || (u['full_name'] ?? '').toLowerCase().contains(q);
  }).toList();

  String _fmtTokens(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  Map<int, String> get _userNameMap {
    final map = <int, String>{};
    for (final u in _users) {
      final id = (u['id'] as num?)?.toInt();
      if (id == null) continue;
      map[id] = (u['full_name'] != null && u['full_name'].toString().isNotEmpty)
          ? u['full_name'].toString()
          : u['email']?.toString() ?? 'Пользователь #$id';
    }
    return map;
  }

  Map<int, String> _classNameMapFrom(List<Map<String, dynamic>> classes) {
    final map = <int, String>{};
    for (final c in classes) {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) continue;
      map[id] = c['title']?.toString() ?? 'Класс #$id';
    }
    return map;
  }

  List<Map<String, dynamic>> _perUserSummary() {
    final names = _userNameMap;
    final map   = <int, Map<String, dynamic>>{};
    for (final l in _aiLogs) {
      final uid = (l['user_id'] as num?)?.toInt();
      if (uid == null) continue;
      final tokens = (l['total_tokens'] as num? ?? 0).toInt();
      if (map.containsKey(uid)) {
        map[uid]!['tokens'] = (map[uid]!['tokens'] as int) + tokens;
        map[uid]!['count']  = (map[uid]!['count']  as int) + 1;
      } else {
        map[uid] = {'name': names[uid] ?? 'Пользователь #$uid', 'tokens': tokens, 'count': 1};
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => (b['tokens'] as int).compareTo(a['tokens'] as int));
    return list;
  }

  List<dynamic> _membersForClass(int classId) {
    return _classMembers[classId] ?? [];
  }

  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final l        = context.watch<L10n>();
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final surface  = Theme.of(context).colorScheme.surface;
    final primary  = Theme.of(context).colorScheme.primary;
    final teachers = _users.where((u) => u['role'] == 'teacher').length;
    final students = _users.where((u) => u['role'] == 'student').length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverToBoxAdapter(child: Column(children: [
            // ── Title + Add button ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [primary, Theme.of(context).colorScheme.secondary]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: primaryGlow(primary, opacity: 0.32),
                  ),
                  child: const Icon(CupertinoIcons.shield_fill, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('admin'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: adaptiveText1(context), letterSpacing: -0.5)),
                  Text(l.t('admin_sub'), style: const TextStyle(fontSize: 12, color: C.text4)),
                ])),
                GestureDetector(
                  onTap: _showCreateDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(12), boxShadow: primaryGlow(primary, opacity: 0.28)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.person_badge_plus, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text('Добавить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
              ]),
            ),
            // ── Stats row (scrolls away) ───────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                _StatCard(icon: CupertinoIcons.person_2,   value: '${_users.length}', label: l.t('total_label'),    color: primary,                    isDark: isDark),
                const SizedBox(width: 8),
                _StatCard(icon: CupertinoIcons.book,       value: '$teachers',        label: l.t('teachers_label'), color: const Color(0xFF6366F1), isDark: isDark),
                const SizedBox(width: 8),
                _StatCard(icon: CupertinoIcons.person,     value: '$students',        label: l.t('students_label'), color: const Color(0xFF059669), isDark: isDark),
              ]),
            ),
          ])),
        ],
        // ── Tabs + content stay pinned ──────────────────────
        body: Column(children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: softShadow(isDark),
            ),
            child: TabBar(
              controller: _tabCtrl,
              labelColor: primary,
              unselectedLabelColor: C.text4,
              indicatorColor: primary,
              indicatorSize: TabBarIndicatorSize.label,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: [Tab(text: l.t('users')), const Tab(text: 'AI'), Tab(text: l.t('class_tab'))],
            ),
          ),
          Expanded(child: TabBarView(controller: _tabCtrl, children: [
            _usersTab(),
            _aiTab(),
            _classesTab(),
          ])),
        ]),
      )),
    );
  }

  // ── Users tab ────────────────────────────────────────────
  Widget _usersTab() {
    final l       = context.read<L10n>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final filtered = _filtered;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TextField(
          decoration: InputDecoration(
            hintText: l.t('search_users'),
            prefixIcon: const Padding(padding: EdgeInsets.only(left: 4),
              child: Icon(CupertinoIcons.search, size: 18, color: C.text4)),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
      ),
      Expanded(child: _loading
        ? Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5))
        : RefreshIndicator(
            color: primary,
            onRefresh: _load,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final u    = filtered[i];
                final name = u['full_name'] ?? u['email']?.split('@').first ?? '';
                final role = u['role'] ?? 'student';
                final isBlocked = u['is_active'] == false;

                return TweenAnimationBuilder<double>(
                  key: ValueKey(u['id']),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + i * 40),
                  curve: Curves.easeOutCubic,
                  builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 12 * (1-t)), child: child)),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: softShadow(isDark),
                    ),
                    child: Row(children: [
                      // Avatar
                      Container(
                        width: 46, height: 46,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(colors: [primary.withOpacity(0.22), primary.withOpacity(0.07)]),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 18),
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                          if (isBlocked) Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: C.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Text('блок', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.red)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(u['email'] ?? '', style: const TextStyle(fontSize: 12, color: C.text4), overflow: TextOverflow.ellipsis),
                      ])),
                      const SizedBox(width: 8),
                      _RoleBadge(role: role),
                      PopupMenuButton<String>(
                        icon: const Icon(CupertinoIcons.ellipsis, size: 20, color: C.text4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        onSelected: (v) => _action(u, v),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'student', child: Text(l.t('set_student'))),
                          PopupMenuItem(value: 'teacher', child: Text(l.t('set_teacher'))),
                          PopupMenuItem(value: 'admin',   child: Text(l.t('set_admin'))),
                          const PopupMenuDivider(),
                          PopupMenuItem(value: isBlocked ? 'unblock' : 'block',
                            child: Text(isBlocked ? l.t('unblock') : l.t('block'))),
                          PopupMenuItem(value: 'delete',
                            child: Text(l.t('delete'), style: const TextStyle(color: C.red))),
                        ],
                      ),
                    ]),
                  ),
                );
              },
            ),
          )),
    ]);
  }

  // ── AI tab ───────────────────────────────────────────────
  Widget _aiTab() {
    final l       = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    if (_aiLoading) return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));

    final classes      = _allClassPosts;
    final classNames   = _classNameMapFrom(classes);
    final userNames    = _userNameMap;
    final userSummary  = _perUserSummary();
    final maxTokens    = userSummary.isNotEmpty ? (userSummary.first['tokens'] as int) : 1;

    return RefreshIndicator(
      color: primary,
      onRefresh: _loadAi,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 90), children: [

        // Total tokens card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(20),
            boxShadow: primaryGlow(primary, opacity: 0.32),
          ),
          child: Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: const Icon(CupertinoIcons.bolt_fill, color: Colors.white, size: 26)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('total_tokens'), style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(_fmtTokens(_totalTokens), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
            ])),
            GestureDetector(
              onTap: _loadAi,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.arrow_counterclockwise, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(l.t('refresh'), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),

        // By class
        if (_aiSummary.isNotEmpty) ...[
          _SectionLabel(l.t('by_classes')),
          const SizedBox(height: 8),
          ..._aiSummary.asMap().entries.map((entry) {
            final i   = entry.key;
            final s   = entry.value;
            final cid = (s['class_id'] as num?)?.toInt();
            final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : 'Без класса';
            final tokens    = (s['total_tokens'] as num? ?? 0).toInt();
            final reqCount  = (s['request_count'] as num? ?? 0).toInt();
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 280 + i * 40),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1-t)), child: child)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: primary.withOpacity(0.10), borderRadius: BorderRadius.circular(13)),
                    child: Icon(CupertinoIcons.book, size: 20, color: primary)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(className, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('$reqCount ${l.t('requests_count')}', style: const TextStyle(fontSize: 11, color: C.text4)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmtTokens(tokens), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    const Text('токенов', style: TextStyle(fontSize: 10, color: C.text4)),
                  ]),
                ]),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],

        // By user
        if (userSummary.isNotEmpty) ...[
          _SectionLabel(l.t('by_users')),
          const SizedBox(height: 8),
          ...userSummary.asMap().entries.map((entry) {
            final i      = entry.key;
            final u      = entry.value;
            final name   = u['name'] as String;
            final tokens = u['tokens'] as int;
            final count  = u['count'] as int;
            final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
            final pct = maxTokens > 0 ? (tokens / maxTokens).clamp(0.0, 1.0) : 0.0;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + i * 40),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10*(1-t)), child: child)),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(gradient: RadialGradient(colors: [primary.withOpacity(0.22), primary.withOpacity(0.06)]), shape: BoxShape.circle),
                    child: Center(child: Text(initials, style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 15)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis, maxLines: 1),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: pct, backgroundColor: primary.withOpacity(0.08), color: primary, minHeight: 5)),
                    const SizedBox(height: 3),
                    Text('$count запр.', style: const TextStyle(fontSize: 10, color: C.text4)),
                  ])),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmtTokens(tokens), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    const Text('токенов', style: TextStyle(fontSize: 10, color: C.text4)),
                  ]),
                ]),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],

        // Log table
        if (_aiLogs.isNotEmpty) ...[
          _SectionLabel('${l.t('detail_log')} (${_aiLogs.length})'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
            child: Column(children: [
              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(children: [
                  const SizedBox(width: 22, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
                  const Expanded(flex: 3, child: Text('ПОЛЬЗОВАТЕЛЬ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5))),
                  const Expanded(flex: 2, child: Text('КЛАСС', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5))),
                  SizedBox(width: 60, child: const Text('ТОКЕНЫ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5), textAlign: TextAlign.right)),
                ]),
              ),
              Divider(height: 1, color: C.border.withOpacity(0.5)),
              ...List.generate(_aiLogs.length, (i) {
                final entry     = _aiLogs[i];
                final uid       = (entry['user_id'] as num?)?.toInt();
                final cid       = (entry['class_id'] as num?)?.toInt();
                final userName  = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
                final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : '—';
                final isGrade   = (entry['endpoint'] ?? '').toString().contains('grade');
                final date = entry['created_at'] != null ? (() {
                  try { final d = DateTime.parse(entry['created_at']); return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; }
                  catch (_) { return ''; }
                })() : '';
                return Container(
                  decoration: BoxDecoration(
                    color: i.isOdd ? adaptiveSurface2(context).withOpacity(0.4) : Colors.transparent,
                    borderRadius: i == _aiLogs.length - 1 ? const BorderRadius.vertical(bottom: Radius.circular(16)) : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(children: [
                    SizedBox(width: 22, child: Text('${i+1}', style: const TextStyle(fontSize: 10, color: C.text4))),
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(userName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      Text(date, style: const TextStyle(fontSize: 9, color: C.text4)),
                    ])),
                    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(className, style: const TextStyle(fontSize: 11, color: C.text4), overflow: TextOverflow.ellipsis),
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isGrade ? primary.withOpacity(0.1) : C.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isGrade ? 'Проверка' : 'Чат', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isGrade ? primary : C.green)),
                      ),
                    ])),
                    SizedBox(width: 60, child: Text('${entry['total_tokens'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary), textAlign: TextAlign.right)),
                  ]),
                );
              }),
            ]),
          ),
        ],

        if (_aiSummary.isEmpty && _aiLogs.isEmpty)
          Padding(padding: const EdgeInsets.all(48), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(CupertinoIcons.bolt, size: 52, color: C.text4),
            const SizedBox(height: 14),
            Text(l.t('no_ai_data'), style: const TextStyle(color: C.text4, fontSize: 15, fontWeight: FontWeight.w600)),
          ]))),
      ]),
    );
  }

  // ── Classes tab ──────────────────────────────────────────
  Widget _classesTab() {
    final l       = context.read<L10n>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    if (_classesLoading) return Center(child: CircularProgressIndicator(color: primary, strokeWidth: 2.5));

    final classes   = _allClassPosts;
    final userNames = _userNameMap;

    if (classes.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(CupertinoIcons.book, size: 52, color: C.text4),
      const SizedBox(height: 14),
      Text(l.t('no_classes_admin'), style: const TextStyle(color: C.text4, fontSize: 15, fontWeight: FontWeight.w600)),
    ]));

    return RefreshIndicator(
      color: primary,
      onRefresh: () async { await _load(); await _loadClasses(); },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        itemCount: classes.length,
        itemBuilder: (ctx, i) {
          final cls         = classes[i];
          final classId     = (cls['id'] as num?)?.toInt() ?? 0;
          final title       = cls['title']?.toString() ?? '';
          final coverImg    = cls['cover_image'];
          final uid         = (cls['user_id'] as num?)?.toInt();
          final creatorName = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
          final description = (cls['description'] ?? '').toString();
          final group       = (cls['group'] ?? '').toString();
          final teacherName = (cls['teacher_name'] ?? '').toString();
          final members     = _membersForClass(classId);
          final students    = members.where((m) => (m['role'] ?? '') == 'student').toList();
          final surface     = Theme.of(context).colorScheme.surface;

          return TweenAnimationBuilder<double>(
            key: ValueKey(cls['id']),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 320 + i * 50),
            curve: Curves.easeOutCubic,
            builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 16*(1-t)), child: child)),
            child: GestureDetector(
              onTap: () => _showStudentsSheet(classId, title, coverImg, i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20), boxShadow: cardShadow(isDark)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Cover
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: SizedBox(height: 128, width: double.infinity,
                      child: Stack(fit: StackFit.expand, children: [
                        _classCover(coverImg, i),
                        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          stops: const [0.5, 1.0], colors: [Colors.transparent, Colors.black.withOpacity(0.42)],
                        )))),
                        Positioned(top: 10, right: 10, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withOpacity(0.52), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.person_2, size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text('${members.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                          ]),
                        )),
                      ])),
                  ),
                  // Info
                  Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: adaptiveText1(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3),
                      child: Text(description, style: const TextStyle(fontSize: 13, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(height: 10),
                    // Creator row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(color: primary.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Container(width: 30, height: 30,
                          decoration: BoxDecoration(color: primary.withOpacity(0.16), shape: BoxShape.circle),
                          child: Center(child: Text(
                            creatorName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join().isNotEmpty
                                ? creatorName.trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join()
                                : '?',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: primary),
                          ))),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.t('created_by'), style: const TextStyle(fontSize: 10, color: C.text4, fontWeight: FontWeight.w500)),
                          Text(creatorName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary), overflow: TextOverflow.ellipsis),
                        ])),
                        if (group.isNotEmpty) Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                          child: Text(group, style: const TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w700))),
                      ]),
                    ),
                    if (teacherName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        const Icon(CupertinoIcons.person, size: 13, color: C.text4),
                        const SizedBox(width: 4),
                        Text(teacherName, style: const TextStyle(fontSize: 12, color: C.text4)),
                      ])),
                    const SizedBox(height: 10),
                    // Students preview
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: adaptiveSurface2(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primary.withOpacity(0.18)),
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: students.isEmpty ? 0 : (students.length == 1 ? 28 : students.length == 2 ? 46 : 64),
                          height: 28,
                          child: Stack(children: students.take(3).toList().asMap().entries.map((e) {
                            final s = e.value;
                            final nm = (s['full_name'] ?? s['email'] ?? '').toString();
                            return Positioned(left: e.key * 18.0, child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(color: primary, shape: BoxShape.circle,
                                border: Border.all(color: adaptiveSurface2(context), width: 2)),
                              child: Center(child: Text(nm.trim().isEmpty ? '?' : nm.trim()[0].toUpperCase(),
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)))));
                          }).toList()),
                        ),
                        SizedBox(width: students.isEmpty ? 0 : 10),
                        Expanded(child: students.isEmpty
                          ? Text(l.t('no_students_class'), style: const TextStyle(fontSize: 13, color: C.text4))
                          : Text('${students.length} ${l.t('students_count')}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary))),
                        Icon(CupertinoIcons.chevron_right, size: 13, color: primary),
                      ]),
                    ),
                  ])),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Students bottom sheet ─────────────────────────────────
  void _showStudentsSheet(int classId, String className, dynamic coverImg, int colorIdx) {
    final l       = context.read<L10n>();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final members      = _membersForClass(classId);
          final studentCount = members.where((m) => (m['role'] ?? '') == 'student').length;

          Future<void> doRefresh() async {
            final api = context.read<ApiService>();
            try {
              final fresh = await api.getClassMembers(classId);
              if (mounted) setState(() => _classMembers[classId] = fresh);
            } catch (_) {}
            if (mounted) setS(() {});
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.65, maxChildSize: 0.92,
            builder: (ctx, sc) => Column(children: [
              // Handle
              Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),

              // Header
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(12),
                  child: SizedBox(width: 52, height: 52, child: _classCover(coverImg, colorIdx))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(className, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(CupertinoIcons.person_2, size: 13, color: primary),
                    const SizedBox(width: 4),
                    Text('$studentCount ${l.t('students_count')}',
                      style: TextStyle(fontSize: 12, color: primary, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text('всего ${members.length}', style: const TextStyle(fontSize: 12, color: C.text4, fontWeight: FontWeight.w500)),
                  ]),
                ])),
                GestureDetector(
                  onTap: doRefresh,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
                    child: Icon(CupertinoIcons.arrow_counterclockwise, size: 18, color: primary),
                  ),
                ),
              ])),

              Divider(height: 1, color: C.border.withOpacity(0.5)),

              // List
              Expanded(child: members.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(CupertinoIcons.person_2, size: 52, color: C.text4),
                    const SizedBox(height: 14),
                    Text(l.t('no_students_class'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: C.text4)),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: doRefresh,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.arrow_counterclockwise, size: 15, color: primary),
                          const SizedBox(width: 6),
                          Text('Обновить список', style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ]))
                : RefreshIndicator(
                    color: primary,
                    onRefresh: doRefresh,
                    child: ListView.separated(
                      controller: sc,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: members.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, j) {
                        final s        = members[j];
                        final name     = (s['full_name'] ?? '').toString().trim();
                        final email    = (s['email'] ?? '').toString();
                        final role     = (s['role'] ?? '').toString();
                        final sGroup   = (s['group'] ?? '').toString();
                        final display  = name.isNotEmpty ? name : email.split('@').first;
                        final initials = display.trim().isEmpty ? '?' : display.trim()
                            .split(RegExp(r'\s+')).take(2)
                            .map((w) => w.isEmpty ? '' : w[0].toUpperCase()).join();
                        final isTeacher  = role == 'teacher' || role == 'admin';
                        final roleColor  = isTeacher ? const Color(0xFF6366F1) : primary;
                        final roleLabel  = isTeacher ? 'Учитель' : 'Ученик';
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: softShadow(isDark),
                          ),
                          child: Row(children: [
                            Container(width: 44, height: 44,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(colors: [roleColor.withOpacity(0.24), roleColor.withOpacity(0.07)]),
                                shape: BoxShape.circle),
                              child: Center(child: Text(initials,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: roleColor)))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(email, style: const TextStyle(fontSize: 12, color: C.text4)),
                            ])),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: roleColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(roleLabel, style: TextStyle(fontSize: 11, color: roleColor, fontWeight: FontWeight.w700))),
                              if (sGroup.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                                  child: Text(sGroup, style: const TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w700))),
                              ],
                            ]),
                          ]),
                        );
                      },
                    ),
                  )),
            ]),
          );
        },
      ),
    );
  }

  Widget _classCover(dynamic coverImg, int index) {
    const grads = [[Color(0xFF006475), Color(0xFF009AAF)], [Color(0xFF0C4A6E), Color(0xFF0369A1)],
                   [Color(0xFF134E4A), Color(0xFF0D9488)], [Color(0xFF312E81), Color(0xFF4338CA)],
                   [Color(0xFF1E3A5F), Color(0xFF2563EB)]];
    final colors = grads[index % grads.length];
    if (coverImg == null) return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)));
    if (coverImg.toString().startsWith('data:')) {
      try { return Image.memory(base64Decode(coverImg.toString().split(',').last), fit: BoxFit.cover, width: double.infinity); }
      catch (_) { return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))); }
    }
    return CachedNetworkImage(imageUrl: coverImg.toString(), fit: BoxFit.cover, width: double.infinity,
      fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))));
  }

  void _action(dynamic u, String action) async {
    final api = context.read<ApiService>();
    if (u['id'] == context.read<AuthProvider>().userId && ['block', 'delete'].contains(action)) return;
    try {
      switch (action) {
        case 'student': case 'teacher': case 'admin': await api.adminSetRole(u['id'], action); break;
        case 'block':   await api.adminBlock(u['id']); break;
        case 'unblock': await api.adminUnblock(u['id']); break;
        case 'delete':  await api.adminDelete(u['id']); break;
      }
      if (mounted) { showToast(context, context.read<L10n>().t('done')); _load(); }
    } catch (_) { if (mounted) showToast(context, context.read<L10n>().t('error'), error: true); }
  }

  void _showCreateDialog() {
    final emailCtrl = TextEditingController(), pwCtrl = TextEditingController();
    String role = 'student';
    final l = context.read<L10n>();
    showCupertinoDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => CupertinoAlertDialog(
      title: Text(l.t('create_user')),
      content: Padding(padding: const EdgeInsets.only(top: 8), child: Column(mainAxisSize: MainAxisSize.min, children: [
        CupertinoTextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, placeholder: 'Email',
          prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(CupertinoIcons.mail, size: 18, color: C.text4))),
        const SizedBox(height: 8),
        CupertinoTextField(controller: pwCtrl, obscureText: true, placeholder: 'Пароль',
          prefix: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(CupertinoIcons.lock, size: 18, color: C.text4))),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: role,
          decoration: const InputDecoration(prefixIcon: Padding(padding: EdgeInsets.only(left: 4), child: Icon(CupertinoIcons.tag, size: 18, color: C.text4))),
          items: ['student', 'teacher', 'admin'].map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)))).toList(),
          onChanged: (v) => setS(() => role = v!),
        ),
      ])),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx), child: Text(l.t('cancel'))),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () async {
            try {
              await context.read<ApiService>().adminCreateUser(emailCtrl.text.trim(), pwCtrl.text, role);
              if (mounted) { Navigator.pop(ctx); showToast(context, l.t('created')); _load(); }
            } catch (_) { if (mounted) showToast(context, l.t('error'), error: true); }
          },
          child: const Text('Создать'),
        ),
      ],
    )));
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  final bool isDark;
  const _StatCard({required this.icon, required this.value, required this.label, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: softShadow(isDark),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 17, color: color)),
      const SizedBox(height: 8),
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: adaptiveText1(context), height: 1)),
      const SizedBox(height: 1),
      Text(label, style: const TextStyle(fontSize: 11, color: C.text4, fontWeight: FontWeight.w500)),
    ]),
  ));
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = role == 'admin' ? primary : role == 'teacher' ? const Color(0xFF6366F1) : C.text4;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
      child: Text(role, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: C.text4, letterSpacing: 1.0));
}
