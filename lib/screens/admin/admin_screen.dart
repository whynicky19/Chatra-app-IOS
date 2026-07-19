import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_cache.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/toast.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'admin_avatars_tab.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override State<AdminScreen> createState() => _AdminState();
}

class _AdminState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<dynamic> _users   = [];
  List<Map<String, dynamic>> _allClassPosts = [];
  List<dynamic> _aiLogs  = [];
  List<dynamic> _aiSummary = [];
  Map<int, List<dynamic>> _classMembers = {};
  bool _loading       = true;
  bool _aiLoading     = true;
  bool _classesLoading = true;
  String _search      = '';
  int _totalTokens    = 0;
  bool _avatarsTabActive = false;
  int _avatarsPendingCount = 0;
  // AI usage filter/pagination — mirrors the site's aiFilterClass + page/page_size.
  int? _aiFilterClassId;
  int _aiLogPage      = 1;
  int _aiLogTotal     = 0;
  bool _aiLogLoadingMore = false;
  static const _aiLogPageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        final isAvatars = _tabCtrl.index == 3;
        if (_avatarsTabActive != isAvatars) setState(() => _avatarsTabActive = isAvatars);
      }
    });
    _initAll();
  }

  Timer? _searchDebounce;

  // Memoized tab bodies: an unrelated parent setState (tab badge, another tab's
  // data, the avatars callback) returns the SAME cached instance, so Flutter
  // skips rebuilding that tab's subtree and its aggregations. A tab is rebuilt
  // only when its own inputs change (data identity/length, filters, loading,
  // theme, language) — see the signatures below.
  Widget? _usersTabCache, _aiTabCache, _classesTabCache;
  String _usersTabSig = '', _aiTabSig = '', _classesTabSig = '';

  @override void dispose() { _searchDebounce?.cancel(); _tabCtrl.dispose(); super.dispose(); }

  // The three loads are independent — run them in parallel so each tab appears
  // as its own data arrives instead of waiting for the previous request.
  Future<void> _initAll() async {
    await Future.wait([_load(), _loadClasses(), _loadAi()]);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try { _users = await context.read<ApiService>().adminUsers(); } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() => _classesLoading = true);
    final api = context.read<ApiService>();
    var classes = <dynamic>[];
    try { classes = await api.getAllClasses(); } catch (_) {}
    _allClassPosts = classes
        .map((c) => {...c as Map<String, dynamic>, 'title': c['name'], 'teacher_name': c['teacher'], 'user_id': c['created_by']})
        .toList();
    // Fetch real members for each class in parallel
    final results = await Future.wait(_allClassPosts.map((c) async {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) return const MapEntry(0, <dynamic>[]);
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

  Future<void> _loadAi() async {
    if (!mounted) return;
    setState(() => _aiLoading = true);
    try {
      final api = context.read<ApiService>();
      _aiSummary = await api.adminAiSummary();
      final page = await api.adminAiUsagePage(classId: _aiFilterClassId, page: 1, pageSize: _aiLogPageSize);
      _aiLogs    = List<dynamic>.from(page['items'] as List? ?? const []);
      _aiLogTotal = (page['total'] as num?)?.toInt() ?? _aiLogs.length;
      _aiLogPage = 1;
      _recomputeTotalTokens();
    } catch (_) {}
    if (mounted) setState(() => _aiLoading = false);
  }

  // Total tokens matches the site's aiFilterClass behavior: unfiltered sums
  // the per-class summary; filtered shows just that class's total.
  void _recomputeTotalTokens() {
    if (_aiFilterClassId == null) {
      _totalTokens = 0;
      for (final s in _aiSummary) {
        _totalTokens += (s['total_tokens'] as num? ?? 0).toInt();
      }
    } else {
      final match = _aiSummary.firstWhere(
        (s) => (s['class_id'] as num?)?.toInt() == _aiFilterClassId,
        orElse: () => const <String, dynamic>{},
      );
      _totalTokens = (match['total_tokens'] as num? ?? 0).toInt();
    }
  }

  void _setAiFilterClass(int? classId) {
    if (_aiFilterClassId == classId) return;
    setState(() => _aiFilterClassId = classId);
    _loadAi();
  }

  Future<void> _loadMoreAiLogs() async {
    if (_aiLogLoadingMore || _aiLogs.length >= _aiLogTotal) return;
    setState(() => _aiLogLoadingMore = true);
    try {
      final api = context.read<ApiService>();
      final page = await api.adminAiUsagePage(classId: _aiFilterClassId, page: _aiLogPage + 1, pageSize: _aiLogPageSize);
      final items = List<dynamic>.from(page['items'] as List? ?? const []);
      if (mounted) setState(() { _aiLogs.addAll(items); _aiLogPage++; });
    } catch (_) {}
    if (mounted) setState(() => _aiLogLoadingMore = false);
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
    // Shared theme+language part of each tab's memo signature — a brightness,
    // primary-color or locale change invalidates all cached tab bodies.
    final tabSig = '$isDark|$primary|${l.lang}';

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
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    boxShadow: primaryGlow(primary, opacity: 0.32),
                  ),
                  child: const Icon(CupertinoIcons.shield_fill, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('admin'), style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: adaptiveText1(context), letterSpacing: -0.5, height: 1.05)),
                  Text(l.t('admin_sub'), style: const TextStyle(fontSize: 12.5, color: C.text4)),
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
              tabs: [
                Tab(text: l.t('users')),
                const Tab(text: 'AI'),
                Tab(text: l.t('class_tab')),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(l.t('admin_avatars_tab'), overflow: TextOverflow.ellipsis, maxLines: 1)),
                  if (_avatarsPendingCount > 0) Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: C.red, borderRadius: BorderRadius.circular(AppRadii.chip)),
                      child: Text('$_avatarsPendingCount', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ])),
              ],
            ),
          ),
          Expanded(child: TabBarView(controller: _tabCtrl, children: [
            _memoUsersTab(tabSig),
            _memoAiTab(tabSig),
            _memoClassesTab(tabSig),
            AdminAvatarsTab(
              isActive: _avatarsTabActive,
              onPendingCountChanged: (count) {
                if (mounted && _avatarsPendingCount != count) setState(() => _avatarsPendingCount = count);
              },
            ),
          ])),
        ]),
      )),
    );
  }

  // ── Tab memoization ──────────────────────────────────────
  // [tl] is a common theme+language signature so a dark/light or locale switch
  // still rebuilds every tab. Data lists are reassigned wholesale on load (so
  // identityHashCode detects reloads); _aiLogs is the exception — _loadMoreAiLogs
  // mutates it in place, hence its length is part of the signature too.
  Widget _memoUsersTab(String tl) {
    final sig = 'u|$_loading|${identityHashCode(_users)}|$_search|$tl';
    if (sig != _usersTabSig || _usersTabCache == null) {
      _usersTabSig = sig;
      _usersTabCache = _usersTab();
    }
    return _usersTabCache!;
  }

  Widget _memoAiTab(String tl) {
    final sig = 'a|$_aiLoading|${identityHashCode(_aiLogs)}|${_aiLogs.length}|$_aiLogPage'
        '|${identityHashCode(_aiSummary)}|${identityHashCode(_allClassPosts)}'
        '|${identityHashCode(_users)}|$_aiFilterClassId|$_aiLogLoadingMore'
        '|$_aiLogTotal|$_totalTokens|$tl';
    if (sig != _aiTabSig || _aiTabCache == null) {
      _aiTabSig = sig;
      _aiTabCache = _aiTab();
    }
    return _aiTabCache!;
  }

  Widget _memoClassesTab(String tl) {
    final sig = 'c|$_classesLoading|${identityHashCode(_allClassPosts)}'
        '|${identityHashCode(_classMembers)}|${identityHashCode(_users)}|$tl';
    if (sig != _classesTabSig || _classesTabCache == null) {
      _classesTabSig = sig;
      _classesTabCache = _classesTab();
    }
    return _classesTabCache!;
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
          // Debounced: the field stays responsive, but filtering (which rebuilds
          // the whole admin screen, incl. the AI/classes tabs) fires only after a
          // short pause instead of on every keystroke.
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _search = v);
            });
          },
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
                  child: RepaintBoundary(child: Container(
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
                          gradient: RadialGradient(colors: [primary.withValues(alpha: 0.22), primary.withValues(alpha: 0.07)]),
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
                            decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: const Text('блок', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.red)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(u['email'] ?? '', style: const TextStyle(fontSize: 12, color: C.text4), overflow: TextOverflow.ellipsis),
                      ])),
                      const SizedBox(width: 8),
                      _RoleBadge(role: role),
                      GestureDetector(
                        onTap: () => _showUserActionsSheet(u),
                        child: Container(
                          width: 34, height: 34,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                          child: const Icon(CupertinoIcons.ellipsis, size: 17, color: C.text4),
                        ),
                      ),
                    ]),
                  )),
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
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: primaryGlow(primary, opacity: 0.32),
          ),
          child: Row(children: [
            Container(width: 48, height: 48,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadii.tile)),
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
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadii.chip)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.arrow_counterclockwise, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(l.t('refresh'), style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),

        // Class filter — like aiFilterClass on the site: filters both the
        // total-tokens card (via _recomputeTotalTokens) and the log below.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _AiFilterChip(label: l.t('filter_all'), selected: _aiFilterClassId == null, onTap: () => _setAiFilterClass(null)),
            const SizedBox(width: 8),
            ...classes.map((c) {
              final cid = (c['id'] as num?)?.toInt();
              if (cid == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _AiFilterChip(
                  label: classNames[cid] ?? 'Класс #$cid',
                  selected: _aiFilterClassId == cid,
                  onTap: () => _setAiFilterClass(cid),
                ),
              );
            }),
          ]),
        ),
        const SizedBox(height: 20),

        // By class
        if (_aiFilterClassId == null && _aiSummary.isNotEmpty) ...[
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
              child: RepaintBoundary(child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(13)),
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
              )),
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
              child: RepaintBoundary(child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
                child: Row(children: [
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(gradient: RadialGradient(colors: [primary.withValues(alpha: 0.22), primary.withValues(alpha: 0.06)]), shape: BoxShape.circle),
                    child: Center(child: Text(initials, style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 15)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis, maxLines: 1),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: pct, backgroundColor: primary.withValues(alpha: 0.08), color: primary, minHeight: 5)),
                    const SizedBox(height: 3),
                    Text('$count запр.', style: const TextStyle(fontSize: 10, color: C.text4)),
                  ])),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_fmtTokens(tokens), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: primary)),
                    const Text('токенов', style: TextStyle(fontSize: 10, color: C.text4)),
                  ]),
                ]),
              )),
            );
          }),
          const SizedBox(height: 20),
        ],

        // Log table
        if (_aiLogs.isNotEmpty) ...[
          _SectionLabel('${l.t('detail_log')} (${_aiLogs.length}/$_aiLogTotal)'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), boxShadow: softShadow(isDark)),
            child: Column(children: [
              // Header row
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4))),
                  Expanded(flex: 3, child: Text('ПОЛЬЗОВАТЕЛЬ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5))),
                  Expanded(flex: 2, child: Text('КЛАСС', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5))),
                  SizedBox(width: 74, child: Text('ТОКЕНЫ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.5), textAlign: TextAlign.right)),
                ]),
              ),
              Divider(height: 1, color: C.border.withValues(alpha: 0.5)),
              ...List.generate(_aiLogs.length, (i) {
                final entry     = _aiLogs[i];
                final uid       = (entry['user_id'] as num?)?.toInt();
                final cid       = (entry['class_id'] as num?)?.toInt();
                final userName  = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
                final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : '—';
                final isGrade   = (entry['endpoint'] ?? '').toString().contains('grade');
                final promptTokens     = (entry['prompt_tokens'] as num?)?.toInt() ?? 0;
                final completionTokens = (entry['completion_tokens'] as num?)?.toInt() ?? 0;
                final totalTokens      = (entry['total_tokens'] as num?)?.toInt() ?? (promptTokens + completionTokens);
                final date = entry['created_at'] != null ? (() {
                  try { final d = DateTime.parse(entry['created_at']); return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; }
                  catch (_) { return ''; }
                })() : '';
                return Container(
                  decoration: BoxDecoration(
                    color: i.isOdd ? adaptiveSurface2(context).withValues(alpha: 0.4) : Colors.transparent,
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
                          color: isGrade ? primary.withValues(alpha: 0.1) : C.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isGrade ? 'Проверка' : 'Чат', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: isGrade ? primary : C.green)),
                      ),
                    ])),
                    SizedBox(width: 74, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('$totalTokens', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: primary)),
                      Text('$promptTokens+$completionTokens', style: const TextStyle(fontSize: 9, color: C.text4)),
                    ])),
                  ]),
                );
              }),
              if (_aiLogs.length < _aiLogTotal)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: GestureDetector(
                    onTap: _aiLogLoadingMore ? null : _loadMoreAiLogs,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
                      child: Center(child: _aiLogLoadingMore
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primary))
                          : Text('Показать ещё', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary))),
                    ),
                  ),
                ),
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

    if (classes.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(CupertinoIcons.book, size: 52, color: C.text4),
      const SizedBox(height: 14),
      Text(l.t('no_classes_admin'), style: const TextStyle(color: C.text4, fontSize: 15, fontWeight: FontWeight.w600)),
    ]));
    }

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
            child: RepaintBoundary(child: GestureDetector(
              onTap: () => _showStudentsSheet(classId, title, coverImg, i),
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.card), boxShadow: cardShadow(isDark)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Cover
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    child: SizedBox(height: 128, width: double.infinity,
                      child: Stack(fit: StackFit.expand, children: [
                        _classCover(coverImg, i, classId: classId),
                        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          stops: const [0.5, 1.0], colors: [Colors.transparent, Colors.black.withValues(alpha: 0.42)],
                        )))),
                        Positioned(top: 10, right: 10, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.52), borderRadius: BorderRadius.circular(AppRadii.card)),
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
                      decoration: BoxDecoration(color: primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Container(width: 30, height: 30,
                          decoration: BoxDecoration(color: primary.withValues(alpha: 0.16), shape: BoxShape.circle),
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
                        border: Border.all(color: primary.withValues(alpha: 0.18)),
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
            )),
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
                  child: SizedBox(width: 52, height: 52, child: _classCover(coverImg, colorIdx, classId: classId))),
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
                  onTap: () => _showRejoinableSheet(classId, className, doRefresh),
                  child: Container(
                    width: 36, height: 36,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.chip)),
                    child: Icon(CupertinoIcons.person_badge_plus, size: 18, color: primary),
                  ),
                ),
                GestureDetector(
                  onTap: doRefresh,
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                    child: Icon(CupertinoIcons.arrow_counterclockwise, size: 18, color: primary),
                  ),
                ),
              ])),

              Divider(height: 1, color: C.border.withValues(alpha: 0.5)),

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
                            borderRadius: BorderRadius.circular(AppRadii.tile),
                            boxShadow: softShadow(isDark),
                          ),
                          child: Row(children: [
                            Container(width: 44, height: 44,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(colors: [roleColor.withValues(alpha: 0.24), roleColor.withValues(alpha: 0.07)]),
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
                                decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Text(roleLabel, style: TextStyle(fontSize: 11, color: roleColor, fontWeight: FontWeight.w700))),
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

  // ── Вернуть ранее состоявшего студента (из архивных потоков) ──────────────
  void _showRejoinableSheet(int classId, String className, Future<void> Function() onChanged) {
    final l = context.read<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final api = context.read<ApiService>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) {
        List<dynamic> candidates = [];
        bool loading = true;
        bool started = false;
        final adding = <int>{};

        return StatefulBuilder(builder: (ctx, setS) {
          if (!started) {
            started = true;
            api.getRejoinableStudents(classId).then((v) {
              candidates = v;
              if (ctx.mounted) setS(() => loading = false);
            }).catchError((_) {
              if (ctx.mounted) setS(() => loading = false);
            });
          }

          Future<void> add(Map<String, dynamic> u) async {
            final id = u['id'] as int;
            setS(() => adding.add(id));
            try {
              await api.addClassMember(classId, id);
              candidates.removeWhere((c) => c['id'] == id);
              if (mounted) showToast(context, l.t('student_returned'));
              await onChanged();
            } catch (_) {
              if (mounted) showToast(context, l.t('not_found'), error: true);
            }
            if (ctx.mounted) setS(() => adding.remove(id));
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.6, maxChildSize: 0.92,
            builder: (ctx, sc) => Column(children: [
              Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2))),
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('return_student'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('$className · ${l.t('return_student_hint')}',
                      style: const TextStyle(fontSize: 12.5, color: C.text4, height: 1.35)),
                ])),
              Divider(height: 1, color: C.border.withValues(alpha: 0.5)),
              Expanded(child: loading
                ? Center(child: CupertinoActivityIndicator(color: primary))
                : candidates.isEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.person_crop_circle_badge_checkmark, size: 48, color: C.text4.withValues(alpha: 0.6)),
                      const SizedBox(height: 12),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(l.t('no_archived_students'), textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: C.text4, height: 1.4))),
                    ]))
                  : ListView.separated(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: candidates.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final u = candidates[i] as Map<String, dynamic>;
                        final display = (u['full_name'] ?? u['email'] ?? '').toString();
                        final email = (u['email'] ?? '').toString();
                        final initials = display.trim().isEmpty ? '?' : display.trim()[0].toUpperCase();
                        final busy = adding.contains(u['id']);
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppRadii.tile),
                            boxShadow: softShadow(isDark),
                          ),
                          child: Row(children: [
                            Container(width: 44, height: 44,
                              decoration: BoxDecoration(
                                gradient: RadialGradient(colors: [primary.withValues(alpha: 0.24), primary.withValues(alpha: 0.07)]),
                                shape: BoxShape.circle),
                              child: Center(child: Text(initials,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: primary)))),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(display, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(email, style: const TextStyle(fontSize: 12, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ])),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: busy ? null : () => add(u),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(11)),
                                child: busy
                                  ? const SizedBox(width: 16, height: 16, child: CupertinoActivityIndicator(color: Colors.white))
                                  : Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(CupertinoIcons.add, size: 15, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(l.t('return_add'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                                    ]),
                              ),
                            ),
                          ]),
                        );
                      },
                    )),
            ]),
          );
        });
      },
    );
  }

  Widget _classCover(dynamic coverImg, int index, {int? classId}) {
    const grads = [[Color(0xFF006475), Color(0xFF009AAF)], [Color(0xFF0C4A6E), Color(0xFF0369A1)],
                   [Color(0xFF134E4A), Color(0xFF0D9488)], [Color(0xFF312E81), Color(0xFF4338CA)],
                   [Color(0xFF1E3A5F), Color(0xFF2563EB)]];
    final colors = grads[index % grads.length];
    if (coverImg == null) return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)));
    if (coverImg.toString().startsWith('data:')) {
      final bytes = decodeBase64Image(coverImg.toString());
      return bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true, cacheWidth: 640)
          : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors)));
    }
    return CachedNetworkImage(imageUrl: coverImg.toString(), cacheKey: classId != null ? 'class_cover_$classId' : null, fit: BoxFit.cover, width: double.infinity,
      fadeInDuration: Duration.zero, fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))));
  }

  Future<bool> _action(dynamic u, String action) async {
    final api = context.read<ApiService>();
    if (u['id'] == context.read<AuthProvider>().userId && ['block', 'delete'].contains(action)) return false;
    try {
      switch (action) {
        case 'student': case 'teacher': case 'admin': await api.adminSetRole(u['id'], action); break;
        case 'block':   await api.adminBlock(u['id']); break;
        case 'unblock': await api.adminUnblock(u['id']); break;
        case 'delete':  await api.adminDelete(u['id']); break;
        case 'toggle_ai_unlimited':
          await api.adminSetAiUnlimited(u['id'], u['ai_unlimited'] != true);
          break;
      }
      if (mounted) { showToast(context, context.read<L10n>().t('done')); _load(); }
      return true;
    } catch (_) {
      if (mounted) showToast(context, context.read<L10n>().t('error'), error: true);
      return false;
    }
  }

  // ── User actions sheet (roles, block, delete) ─────────────
  void _showUserActionsSheet(dynamic u) {
    final l       = context.read<L10n>();
    final isSelf  = u['id'] == context.read<AuthProvider>().userId;
    final name    = (u['full_name'] ?? u['email']?.split('@').first ?? '').toString();
    final email   = (u['email'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final primary     = Theme.of(ctx).colorScheme.primary;
        final role        = (u['role'] ?? 'student').toString();
        final isBlocked   = u['is_active'] == false;
        final aiUnlimited = u['ai_unlimited'] == true;

        Widget roleTile(String value, String label, IconData icon, Color color) {
          final selected = role == value;
          return Expanded(child: GestureDetector(
            onTap: selected ? null : () async {
              final ok = await _action(u, value);
              if (ok && ctx.mounted) setS(() => u['role'] = value);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? color.withValues(alpha: 0.12) : adaptiveSurface2(ctx),
                borderRadius: BorderRadius.circular(AppRadii.tile),
                border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
              ),
              child: Column(children: [
                Icon(icon, size: 20, color: selected ? color : C.text4),
                const SizedBox(height: 5),
                Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: selected ? color : C.text4)),
              ]),
            ),
          ));
        }

        Widget actionTile({required IconData icon, required Color color, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap}) {
          return GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: adaptiveSurface2(ctx).withValues(alpha: 0.6), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: Row(children: [
                Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.chip)),
                  child: Icon(icon, size: 18, color: color)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: adaptiveText1(ctx))),
                  if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle, style: const TextStyle(fontSize: 11.5, color: C.text4))),
                ])),
                trailing ?? const Icon(CupertinoIcons.chevron_right, size: 14, color: C.text4),
              ]),
            ),
          );
        }

        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: adaptiveBorder(ctx), borderRadius: BorderRadius.circular(2)))),

            // Header: avatar + name + email
            Row(children: [
              Container(width: 50, height: 50,
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [primary.withValues(alpha: 0.22), primary.withValues(alpha: 0.07)]),
                  shape: BoxShape.circle),
                child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: primary, fontWeight: FontWeight.w900, fontSize: 19)))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: adaptiveText1(ctx)), overflow: TextOverflow.ellipsis)),
                  if (isBlocked) Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: C.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: const Text('блок', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.red)),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(email, style: const TextStyle(fontSize: 12.5, color: C.text4), overflow: TextOverflow.ellipsis),
              ])),
              _RoleBadge(role: role),
            ]),
            const SizedBox(height: 18),

            // Role selector
            const _SectionLabel('РОЛЬ'),
            const SizedBox(height: 8),
            Row(children: [
              roleTile('student', 'Ученик',  CupertinoIcons.person,      const Color(0xFF059669)),
              const SizedBox(width: 8),
              roleTile('teacher', 'Учитель', CupertinoIcons.book,        const Color(0xFF6366F1)),
              const SizedBox(width: 8),
              roleTile('admin',   'Админ',   CupertinoIcons.shield_fill, primary),
            ]),
            const SizedBox(height: 18),

            // Actions
            const _SectionLabel('ДЕЙСТВИЯ'),
            const SizedBox(height: 8),
            actionTile(
              icon: aiUnlimited ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
              color: C.amber,
              title: 'Безлимитный ИИ',
              subtitle: aiUnlimited ? 'Включён — лимиты не действуют' : 'Выключен — обычные лимиты',
              trailing: IgnorePointer(child: Switch(value: aiUnlimited, onChanged: (_) {})),
              onTap: () async {
                final ok = await _action(u, 'toggle_ai_unlimited');
                if (ok && ctx.mounted) setS(() => u['ai_unlimited'] = !aiUnlimited);
              },
            ),
            if (!isSelf) actionTile(
              icon: isBlocked ? CupertinoIcons.lock_open : CupertinoIcons.nosign,
              color: isBlocked ? C.green : C.red,
              title: isBlocked ? l.t('unblock') : l.t('block'),
              subtitle: isBlocked ? 'Вернуть доступ к аккаунту' : 'Пользователь не сможет войти',
              onTap: () async {
                final action = isBlocked ? 'unblock' : 'block';
                if (!isBlocked) {
                  final sure = await showConfirmDialog(context,
                    title: '${l.t('block')}?',
                    message: '$name больше не сможет войти в приложение.',
                    icon: CupertinoIcons.nosign, danger: true,
                    confirmText: l.t('block'), cancelText: l.t('cancel'));
                  if (sure != true) return;
                }
                final ok = await _action(u, action);
                if (ok && ctx.mounted) setS(() => u['is_active'] = isBlocked);
              },
            ),
            if (!isSelf) actionTile(
              icon: CupertinoIcons.trash,
              color: C.red,
              title: l.t('delete'),
              subtitle: 'Аккаунт будет удалён навсегда',
              onTap: () async {
                final sure = await showConfirmDialog(context,
                  title: 'Удалить пользователя?',
                  message: 'Аккаунт «$name» и все его данные будут удалены навсегда.',
                  icon: CupertinoIcons.trash, danger: true,
                  confirmText: l.t('delete'), cancelText: l.t('cancel'));
                if (sure != true) return;
                final ok = await _action(u, 'delete');
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ]),
        ));
      }),
    );
  }

  // ── Create user dialog ────────────────────────────────────
  void _showCreateDialog() {
    final emailCtrl = TextEditingController(), pwCtrl = TextEditingController();
    String role = 'student';
    String? error;
    bool busy = false, obscure = true;
    final l = context.read<L10n>();

    showAppDialog(context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final primary = Theme.of(ctx).colorScheme.primary;

      Future<void> submit() async {
        final email = emailCtrl.text.trim();
        if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
          setS(() => error = 'Введите корректный email');
          return;
        }
        if (pwCtrl.text.length < 6) {
          setS(() => error = 'Пароль — минимум 6 символов');
          return;
        }
        setS(() { busy = true; error = null; });
        try {
          await context.read<ApiService>().adminCreateUser(email, pwCtrl.text, role);
          if (mounted && ctx.mounted) { Navigator.pop(ctx); showToast(context, l.t('created')); _load(); }
        } catch (_) {
          if (ctx.mounted) setS(() { busy = false; error = 'Не удалось создать пользователя'; });
        }
      }

      Widget roleChip(String value, String label, IconData icon, Color color) {
        final selected = role == value;
        return Expanded(child: GestureDetector(
          onTap: busy ? null : () => setS(() => role = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withValues(alpha: 0.12) : adaptiveSurface2(ctx),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? color : Colors.transparent, width: 1.5),
            ),
            child: Column(children: [
              Icon(icon, size: 18, color: selected ? color : C.text4),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? color : C.text4)),
            ]),
          ),
        ));
      }

      return AppDialogCard(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AppDialogIcon(icon: CupertinoIcons.person_badge_plus, color: primary)),
        const SizedBox(height: 14),
        Text(l.t('create_user'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(ctx), letterSpacing: -0.3)),
        const SizedBox(height: 18),
        TextField(
          controller: emailCtrl,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Email',
            prefixIcon: Icon(CupertinoIcons.mail, size: 18, color: C.text4),
          ),
          onChanged: (_) { if (error != null) setS(() => error = null); },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: pwCtrl,
          enabled: !busy,
          obscureText: obscure,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Пароль',
            prefixIcon: const Icon(CupertinoIcons.lock, size: 18, color: C.text4),
            suffixIcon: GestureDetector(
              onTap: () => setS(() => obscure = !obscure),
              child: Icon(obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18, color: C.text4),
            ),
          ),
          onChanged: (_) { if (error != null) setS(() => error = null); },
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 14),
        Row(children: [
          roleChip('student', 'Ученик',  CupertinoIcons.person,      const Color(0xFF059669)),
          const SizedBox(width: 8),
          roleChip('teacher', 'Учитель', CupertinoIcons.book,        const Color(0xFF6366F1)),
          const SizedBox(width: 8),
          roleChip('admin',   'Админ',   CupertinoIcons.shield_fill, primary),
        ]),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: C.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadii.chip)),
            child: Row(children: [
              const Icon(CupertinoIcons.exclamationmark_circle, size: 15, color: C.red),
              const SizedBox(width: 7),
              Expanded(child: Text(error!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.red))),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        AppDialogActions(
          cancelText: l.t('cancel'),
          confirmText: 'Создать',
          busy: busy,
          onCancel: () => Navigator.pop(ctx),
          onConfirm: submit,
        ),
      ]));
    })).whenComplete(() {
      Future.delayed(const Duration(seconds: 1), () { emailCtrl.dispose(); pwCtrl.dispose(); });
    });
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
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      boxShadow: softShadow(isDark),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // White glyph on a coloured gradient tile with a soft glow — matches the
      // premium tile language used on the home/auth screens.
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.88), color],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.30), blurRadius: 10, spreadRadius: -2, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, size: 19, color: Colors.white),
      ),
      const SizedBox(height: 12),
      Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: adaptiveText1(context), height: 1, letterSpacing: -0.5)),
      const SizedBox(height: 3),
      Text(label, style: const TextStyle(fontSize: 11.5, color: C.text4, fontWeight: FontWeight.w500)),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.card)),
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

class _AiFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AiFilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? primary : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected ? primaryGlow(primary, opacity: 0.28) : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : C.text3)),
      ),
    );
  }
}
