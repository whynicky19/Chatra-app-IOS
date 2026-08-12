import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/errors.dart';
import '../../utils/image_cache.dart';
import '../../utils/dates.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/cupertino_liquid_switch.dart';
import '../../widgets/network_cover_image.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';

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
  int? _aiFilterClassId;
  int _aiLogPage      = 1;
  int _aiLogTotal     = 0;
  bool _aiLogLoadingMore = false;
  static const _aiLogPageSize = 30;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _initAll();
  }

  Timer? _searchDebounce;

  Widget? _usersTabCache, _aiTabCache, _classesTabCache;
  String _usersTabSig = '', _aiTabSig = '', _classesTabSig = '';

  @override void dispose() { _searchDebounce?.cancel(); _tabCtrl.dispose(); super.dispose(); }

  Future<void> _initAll() async {
    await Future.wait([_load(), _loadClasses(), _loadAi(), _loadReports()]);
  }

  // ── Очередь модерации ──────────────────────────────────────────────────
  // Строка 'no_reports' и пуш 'admin_report' в PushService существовали
  // давно, но экрана к ним не было. Без него нечем закрыть требование
  // App Store Guideline 1.2 о реакции на жалобы.
  List<dynamic> _reports = [];
  bool _reportsLoading = true;

  Future<void> _loadReports() async {
    if (mounted) setState(() => _reportsLoading = true);
    try {
      _reports = await context.read<ApiService>().adminReports();
    } catch (e) {
      logError('AdminScreen.loadReports', e);
    }
    if (mounted) setState(() => _reportsLoading = false);
  }

  Future<void> _resolveReport(dynamic r) async {
    final l = context.read<L10n>();
    final id = (r['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showConfirmDialog(
      context,
      title: l.t('report_resolve'),
      confirmText: l.t('report_resolve'),
      cancelText: l.t('cancel'),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiService>().adminResolveReport(id);
      if (!mounted) return;
      _removeReportFromList(id);
      showToast(context, l.t('report_resolved'));
    } catch (e) {
      logError('AdminScreen.resolveReport', e);
      if (mounted) showToast(context, l.t('report_error'), error: true);
    }
  }

  void _removeReportFromList(int id) {
    setState(() => _reports = _reports.where((x) => (x['id'] as num?)?.toInt() != id).toList());
  }

  Future<void> _deleteReportContent(dynamic r) async {
    final l = context.read<L10n>();
    final id = (r['id'] as num?)?.toInt();
    if (id == null) return;
    final ok = await showConfirmDialog(
      context,
      title: l.t('report_delete_content'),
      message: l.t('report_delete_content_msg'),
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiService>().adminDeleteReportContent(id);
      if (!mounted) return;
      _removeReportFromList(id);
      showToast(context, l.t('report_content_deleted'));
    } catch (e) {
      logError('AdminScreen.deleteReportContent', e);
      if (mounted) showToast(context, l.t('report_error'), error: true);
    }
  }

  Widget _reportsTab() {
    final l = context.watch<L10n>();

    if (_reportsLoading && _reports.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 13));
    }
    if (_reports.isEmpty) {
      return CustomScrollView(slivers: [
        CupertinoSliverRefreshControl(onRefresh: _loadReports),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 90, 28, 40),
            child: Column(children: [
              Container(width: 76, height: 76,
                decoration: BoxDecoration(
                  gradient: RadialGradient(colors: [C.green.withValues(alpha: 0.16), C.green.withValues(alpha: 0.03)]),
                  shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.checkmark_shield_fill, size: 32, color: C.green)),
              const SizedBox(height: 18),
              Text(l.t('no_reports'), textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveTextSoft(context))),
            ]),
          ),
        ),
      ]);
    }

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: _loadReports),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, bottomBarClearance(context)),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          childCount: _reports.length,
          (_, i) {
          final r = _reports[i];
          final targetType = (r['target_type'] ?? '').toString();
          final targetKey = switch (targetType) {
            'post' => 'report_target_post',
            'assignment' => 'report_target_assignment',
            'submission' => 'report_target_submission',
            _ => 'report_target_user',
          };
          final reasonKey = switch ((r['reason'] ?? '').toString()) {
            'spam' => 'report_reason_spam',
            'abuse' => 'report_reason_abuse',
            'inappropriate' => 'report_reason_inappropriate',
            'academic' => 'report_reason_academic',
            _ => 'report_reason_other',
          };
          final comment = (r['comment'] ?? '').toString();
          final reporter = (r['reporter_name'] ?? r['reporter_email'] ?? '').toString();
          final className = (r['class_name'] ?? '').toString();
          final targetTitle = (r['target_title'] ?? '').toString();
          final canDeleteContent = targetType == 'post' || targetType == 'assignment';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GroupRow.card(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  // Причина жалобы — капсула; справа время, как в списках Mail.
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: C.red.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(l.t(reasonKey),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: C.red)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${l.t(targetKey)} #${r['target_id']}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
                  ),
                  const SizedBox(width: 8),
                  Text(fmtDateTimeLocal((r['created_at'] ?? '').toString()),
                      style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                ]),
                if (className.isNotEmpty || targetTitle.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (className.isNotEmpty) '${l.t('report_class_prefix')}: $className',
                      if (targetTitle.isNotEmpty) targetTitle,
                    ].join('  ·  '),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                  ),
                ],
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(comment,
                      style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.2, color: adaptiveText2(context))),
                ],
                if (reporter.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('${l.t('report')}: $reporter',
                      style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                ],
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  _ReportActionChip(
                    label: l.t('report_resolve'),
                    color: Theme.of(context).colorScheme.primary,
                    onTap: () => _resolveReport(r),
                  ),
                  if (canDeleteContent)
                    _ReportActionChip(
                      label: l.t('report_delete_content'),
                      color: C.red,
                      onTap: () => _deleteReportContent(r),
                    ),
                ]),
              ]),
            ),
          );
          },
        )),
      ),
    ]);
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
    final results = await Future.wait(_allClassPosts.map((c) async {
      final id = (c['id'] as num?)?.toInt();
      if (id == null) return const MapEntry(0, <dynamic>[]);
      try {
        final members = await api.getClassMembers(id, isAdmin: true);
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

  @override
  Widget build(BuildContext context) {
    final l        = context.watch<L10n>();
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final surface  = Theme.of(context).colorScheme.surface;
    final primary  = Theme.of(context).colorScheme.primary;
    final teachers = _users.where((u) => u['role'] == 'teacher').length;
    final students = _users.where((u) => u['role'] == 'student').length;
    final tabSig = '$isDark|$primary|${l.lang}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // bottom: false — та же логика edge-to-edge под навбар, что и на
      // остальных вкладках шелла (см. home_screen.dart). Клиренс над баром
      // держат SliverPadding/SizedBox с bottomBarClearance() в каждой вложенной
      // вкладке (_reportsTab/users/AI/классы) вместо самой SafeArea.
      body: SafeArea(bottom: false, child: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          SliverToBoxAdapter(child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('admin'),
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: adaptiveTextSoft(context))),
                  const SizedBox(height: 3),
                  Text(l.t('admin_sub'),
                      style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context))),
                ])),
                // Добавление — акцентный глиф в баре, как «+» в системных
                // приложениях: залитая пилюля со свечением спорила по весу с
                // самим заголовком экрана.
                Tappable(
                  onTap: _showCreateDialog,
                  label: l.t('add'),
                  child: SizedBox(width: 44, height: 44,
                      child: Icon(CupertinoIcons.person_badge_plus, color: primary, size: 24)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _SummaryBar(cells: [
                ('${_users.length}', l.t('total_label')),
                ('$teachers', l.t('teachers_label')),
                ('$students', l.t('students_label')),
              ]),
            ),
          ])),
        ],
        body: Column(children: [
          Container(
            height: 40,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            padding: const EdgeInsets.all(3),
            // Капсула, как нативный CupertinoSlidingSegmentedControl.
            decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(100)),
            child: TabBar(
              controller: _tabCtrl,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorAnimation: TabIndicatorAnimation.elastic,
              indicator: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08), blurRadius: 3, offset: const Offset(0, 1))],
              ),
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelColor: adaptiveText1(context),
              unselectedLabelColor: adaptiveText3(context),
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: -0.2),
              unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.2),
              tabs: [
                Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(l.t('users')))),
                const Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text('AI'))),
                Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(l.t('class_tab')))),
                Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(l.t('reports_queue')))),
              ],
            ),
          ),
          Expanded(child: TabBarView(controller: _tabCtrl, children: [
            _memoUsersTab(tabSig),
            _memoAiTab(tabSig),
            _memoClassesTab(tabSig),
            _reportsTab(),
          ])),
        ]),
      )),
    );
  }

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

  Widget _usersTab() {
    final l       = context.read<L10n>();
    final filtered = _filtered;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        // Нативное поле поиска iOS: приходит с кнопкой очистки и правильными
        // метриками вместо обычного TextField с иконкой-префиксом.
        child: CupertinoSearchTextField(
          placeholder: l.t('search_users'),
          backgroundColor: adaptiveSurface2(context),
          style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveTextSoft(context)),
          placeholderStyle: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveText4(context)),
          itemColor: adaptiveText4(context),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _search = v);
            });
          },
        ),
      ),
      Expanded(child: _loading
        ? const Center(child: CupertinoActivityIndicator(radius: 13, color: C.text3))
        : CustomScrollView(slivers: [
            CupertinoSliverRefreshControl(onRefresh: _load),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottomBarClearance(context)),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                childCount: filtered.length,
                (ctx, i) {
                final u    = filtered[i];
                final name = u['full_name'] ?? u['email']?.split('@').first ?? '';
                final role = u['role'] ?? 'student';
                final isBlocked = u['is_active'] == false;

                // Без «аватарки»-кружка с первой буквой: имя и почта и так
                // идентифицируют человека, а буква в круге читалась как
                // подмена фотографии. Строка — две строки текста, поэтому все
                // карточки списка одной высоты.
                return Entrance(
                  key: ValueKey(u['id']),
                  index: i,
                  child: RepaintBoundary(child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GroupRow.card(
                      onTap: () => _showUserActionsSheet(u),
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(name,
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (isBlocked) Container(
                              margin: const EdgeInsets.only(left: 7),
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: C.red.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
                              child: Text(l.t('blocked_short'),
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.red)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Text(u['email'] ?? '',
                              style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context)),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        const SizedBox(width: 10),
                        _RoleBadge(role: role),
                        Tappable(
                          onTap: () => _showUserActionsSheet(u),
                          label: 'Действия с пользователем',
                          child: SizedBox(width: 40, height: 46,
                              child: Icon(CupertinoIcons.ellipsis_vertical, size: 18, color: adaptiveText4(context))),
                        ),
                      ]),
                    ),
                  )),
                );
                },
              )),
            ),
          ]),
      ),
    ]);
  }

  Widget _aiTab() {
    final l       = context.read<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final primary = Theme.of(context).colorScheme.primary;

    if (_aiLoading) return const Center(child: CupertinoActivityIndicator(radius: 13, color: C.text3));

    final classes      = _allClassPosts;
    final classNames   = _classNameMapFrom(classes);
    final userNames    = _userNameMap;
    final userSummary  = _perUserSummary();
    final maxTokens    = userSummary.isNotEmpty ? (userSummary.first['tokens'] as int) : 1;

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: _loadAi),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomBarClearance(context)),
        sliver: SliverList(delegate: SliverChildListDelegate([

        // Итог по токенам: тот же градиент, но без цветного свечения под
        // карточкой и с табличными цифрами — число обновляется, и «прыгающая»
        // ширина разрядов бросалась в глаза.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Theme.of(context).colorScheme.secondary, primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Row(children: [
            Container(width: 46, height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadii.tile)),
              child: const Icon(CupertinoIcons.bolt_fill, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('total_tokens').toUpperCase(),
                  style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
              const SizedBox(height: 4),
              Text(_fmtTokens(_totalTokens),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: Colors.white, height: 1,
                      letterSpacing: -1, fontFeatures: [FontFeature.tabularFigures()])),
            ])),
            Tappable(
              onTap: _loadAi,
              label: l.t('refresh'),
              child: SizedBox(width: 44, height: 44,
                  child: Icon(CupertinoIcons.arrow_counterclockwise, size: 20, color: Colors.white.withValues(alpha: 0.9))),
            ),
          ]),
        ),
        const SizedBox(height: 18),

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

        if (_aiFilterClassId == null && _aiSummary.isNotEmpty) ...[
          _SectionLabel(l.t('by_classes')),
          const SizedBox(height: 8),
          ..._aiSummary.asMap().entries.map((entry) {
            final i   = entry.key;
            final s   = entry.value;
            final cid = (s['class_id'] as num?)?.toInt();
            final className = cid != null ? (classNames[cid] ?? 'Класс #$cid') : l.t('no_class_label');
            final tokens    = (s['total_tokens'] as num? ?? 0).toInt();
            final reqCount  = (s['request_count'] as num? ?? 0).toInt();
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 280 + i * 40),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1-t)), child: child)),
              child: RepaintBoundary(child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GroupRow.card(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(children: [
                    Container(width: 46, height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadii.tile)),
                      child: Icon(CupertinoIcons.book_fill, size: 21, color: primary)),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(className,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('$reqCount ${l.t('requests_count')}',
                          style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
                    ])),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(_fmtTokens(tokens),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context),
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      Text(l.t('tokens'), style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                    ]),
                  ]),
                ),
              )),
            );
          }),
          const SizedBox(height: 20),
        ],

        if (userSummary.isNotEmpty) ...[
          _SectionLabel(l.t('by_users')),
          const SizedBox(height: 8),
          ...userSummary.asMap().entries.map((entry) {
            final i      = entry.key;
            final u      = entry.value;
            final name   = u['name'] as String;
            final tokens = u['tokens'] as int;
            final count  = u['count'] as int;
            final pct = maxTokens > 0 ? (tokens / maxTokens).clamp(0.0, 1.0) : 0.0;
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 300 + i * 40),
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10*(1-t)), child: child)),
              child: RepaintBoundary(child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GroupRow.card(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(name,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 10),
                      Text(_fmtTokens(tokens),
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context),
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      Expanded(child: Text('$count ${l.t('requests_label')}',
                          style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context)))),
                      Text(l.t('tokens'), style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                    ]),
                    const SizedBox(height: 10),
                    // Доля этого пользователя от самого активного — полоса на
                    // всю ширину карточки, а не зажатая между кружком и цифрой.
                    ClipRRect(borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(value: pct, backgroundColor: primary.withValues(alpha: 0.10), color: primary, minHeight: 6)),
                  ]),
                ),
              )),
            );
          }),
          const SizedBox(height: 20),
        ],

        if (_aiLogs.isNotEmpty) ...[
          _SectionLabel('${l.t('detail_log')} (${_aiLogs.length}/$_aiLogTotal)'),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadii.card),
              border: Border.all(color: groupSeparator(context), width: hairline(context)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(children: [
                  SizedBox(width: 24, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: adaptiveText4(context)))),
                  Expanded(flex: 3, child: Text(l.t('user_label').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: adaptiveText4(context), letterSpacing: 0.6))),
                  Expanded(flex: 2, child: Text(l.t('class_col').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: adaptiveText4(context), letterSpacing: 0.6))),
                  SizedBox(width: 74, child: Text(l.t('tokens_col').toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: adaptiveText4(context), letterSpacing: 0.6), textAlign: TextAlign.right)),
                ]),
              ),
              Container(height: hairline(context), color: groupSeparator(context)),
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
                final date = (() {
                  final d = parseServerDate(entry['created_at']);
                  if (d == null) return '';
                  return '${d.day.toString().padLeft(2,'0')}.${d.month.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
                })();
                // Строки разделены волосяной линией, без «зебры»: чередование
                // заливки — приём таблиц Material, в системных списках iOS
                // строки разделяет линия по началу контента.
                return Column(children: [
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(height: hairline(context), color: groupSeparator(context)),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      SizedBox(width: 24, child: Text('${i+1}',
                          style: TextStyle(fontSize: 13, color: adaptiveText4(context), fontFeatures: const [FontFeature.tabularFigures()]))),
                      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(userName,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: adaptiveTextSoft(context)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(date, style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                      ])),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(className,
                            style: TextStyle(fontSize: 13, color: adaptiveText4(context)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isGrade ? primary.withValues(alpha: 0.12) : C.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(isGrade ? l.t('check_type') : l.t('chat_type'),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isGrade ? primary : C.green)),
                        ),
                      ])),
                      SizedBox(width: 74, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('$totalTokens',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: adaptiveTextSoft(context),
                                fontFeatures: const [FontFeature.tabularFigures()])),
                        Text('$promptTokens+$completionTokens',
                            style: TextStyle(fontSize: 13, color: adaptiveText4(context),
                                fontFeatures: const [FontFeature.tabularFigures()])),
                      ])),
                    ]),
                  ),
                ]);
              }),
              if (_aiLogs.length < _aiLogTotal) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Container(height: hairline(context), color: groupSeparator(context)),
                ),
                // «Показать ещё» — акцентная текстовая строка в самом списке,
                // как «Load More» в системных приложениях, а не серая кнопка.
                GroupRow(
                  pos: GroupPos.last,
                  color: Colors.transparent,
                  onTap: _aiLogLoadingMore ? null : _loadMoreAiLogs,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Center(child: _aiLogLoadingMore
                      ? CupertinoActivityIndicator(radius: 9, color: adaptiveText4(context))
                      : Text(l.t('show_more_full'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: primary))),
                ),
              ],
            ]),
          ),
        ],

        if (_aiSummary.isEmpty && _aiLogs.isEmpty)
          Padding(padding: const EdgeInsets.fromLTRB(28, 48, 28, 48), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 76, height: 76,
              decoration: BoxDecoration(
                gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.03)]),
                shape: BoxShape.circle),
              child: Icon(CupertinoIcons.bolt_fill, size: 32, color: primary)),
            const SizedBox(height: 18),
            Text(l.t('no_ai_data'), textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveTextSoft(context))),
          ]))),
        ])),
      ),
    ]);
  }

  Widget _classesTab() {
    final l       = context.read<L10n>();
    if (_classesLoading) return const Center(child: CupertinoActivityIndicator(radius: 13, color: C.text3));

    final classes   = _allClassPosts;
    final userNames = _userNameMap;

    if (classes.isEmpty) {
      final primary = Theme.of(context).colorScheme.primary;
      return Center(child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 76, height: 76,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.03)]),
              shape: BoxShape.circle),
            child: Icon(CupertinoIcons.book_fill, size: 32, color: primary)),
          const SizedBox(height: 18),
          Text(l.t('no_classes_admin'), textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveTextSoft(context))),
        ]),
      ));
    }

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: () async { await _load(); await _loadClasses(); }),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomBarClearance(context)),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          childCount: classes.length,
          (ctx, i) {
          final cls         = classes[i];
          final classId     = (cls['id'] as num?)?.toInt() ?? 0;
          final title       = cls['title']?.toString() ?? '';
          final coverImg    = cardCoverUrl(cls);
          final uid         = (cls['user_id'] as num?)?.toInt();
          final creatorName = uid != null ? (userNames[uid] ?? 'Пользователь #$uid') : '—';
          final description = (cls['description'] ?? '').toString();
          final teacherName = (cls['teacher_name'] ?? '').toString();
          final members     = _membersForClass(classId);
          final students    = members.where((m) => (m['role'] ?? '') == 'student').toList();

          // Без стопки кружков-«аватарок» студентов и без кружка автора: состав
          // класса теперь читается словами (кто создал, сколько студентов), а
          // открывается он по нажатию на всю карточку.
          return Entrance(
            key: ValueKey(cls['id']),
            index: i,
            child: RepaintBoundary(child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GroupRow.card(
                onTap: () => _showStudentsSheet(classId, title, coverImg, i),
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 120, width: double.infinity,
                    child: Stack(fit: StackFit.expand, children: [
                      _classCover(coverImg, i),
                      Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        stops: const [0.45, 1.0], colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
                      )))),
                      Positioned(top: 10, right: 10, child: ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            color: Colors.black.withValues(alpha: 0.28),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(CupertinoIcons.person_2_fill, size: 13, color: Colors.white),
                              const SizedBox(width: 5),
                              Text('${members.length}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white,
                                      fontFeatures: [FontFeature.tabularFigures()])),
                            ]),
                          ),
                        ),
                      )),
                    ])),
                  Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.15, color: adaptiveTextSoft(context)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text(description,
                          style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context)),
                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const SizedBox(height: 12),
                    // Метаданные класса — сгруппированной секцией «метка → значение».
                    InsetGroup(
                      color: adaptiveSurface2(context),
                      radius: AppRadii.tile,
                      children: [
                        _metaRow(l.t('created_by'), creatorName, pos: teacherName.isNotEmpty ? GroupPos.middle : GroupPos.last),
                        if (teacherName.isNotEmpty)
                          _metaRow(l.t('role_teacher'), teacherName, pos: GroupPos.last),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(CupertinoIcons.person_2, size: 15, color: adaptiveText4(context)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(students.isEmpty
                            ? l.t('no_students_class')
                            : '${students.length} ${l.t('students_count')}',
                          style: TextStyle(fontSize: 15, letterSpacing: -0.2,
                              color: students.isEmpty ? adaptiveText4(context) : adaptiveText2(context)))),
                    ]),
                  ])),
                ]),
              ),
            )),
          );
          },
        )),
      ),
    ]);
  }

  /// Строка «метка — значение» внутри сгруппированной секции карточки класса.
  Widget _metaRow(String label, String value, {required GroupPos pos}) => GroupRow(
    pos: pos,
    color: Colors.transparent,
    separatorInset: 12,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
      const SizedBox(width: 12),
      Expanded(child: Text(value, textAlign: TextAlign.right,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: adaptiveTextSoft(context)),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );

  void _showStudentsSheet(int classId, String className, dynamic coverImg, int colorIdx) {
    final l       = context.read<L10n>();
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
              final fresh = await api.getClassMembers(classId, isAdmin: true);
              if (mounted) setState(() => _classMembers[classId] = fresh);
            } catch (_) {}
            if (mounted) setS(() {});
          }

          return DraggableScrollableSheet(
            expand: false, initialChildSize: 0.65, maxChildSize: 0.92,
            builder: (ctx, sc) => Column(children: [
              Container(width: 40, height: 5, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: adaptiveText4(context).withValues(alpha: 0.35), borderRadius: BorderRadius.circular(100))),

              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 12, 14), child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(AppRadii.tile),
                  child: SizedBox(width: 52, height: 52, child: _classCover(coverImg, colorIdx))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(className,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5, height: 1.15, color: adaptiveTextSoft(context)),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('$studentCount ${l.t('students_count')}  ·  ${l.t('total_label').toLowerCase()} ${members.length}',
                      style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                // Действия листа — акцентные глифы, как в баре системного
                // приложения, вместо цветных плашек-квадратов.
                Tappable(
                  onTap: () => _showRejoinableSheet(classId, className, doRefresh),
                  label: 'Вернуть студента',
                  child: SizedBox(width: 44, height: 44,
                      child: Icon(CupertinoIcons.person_badge_plus, size: 22, color: primary)),
                ),
                Tappable(
                  onTap: doRefresh,
                  label: 'Обновить',
                  child: SizedBox(width: 44, height: 44,
                      child: Icon(CupertinoIcons.arrow_counterclockwise, size: 20, color: primary)),
                ),
              ])),

              Container(height: hairline(context), color: groupSeparator(context)),

              Expanded(child: members.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.person_2, size: 34, color: adaptiveText4(context).withValues(alpha: 0.7)),
                      const SizedBox(height: 14),
                      Text(l.t('no_students_class'), textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context))),
                      const SizedBox(height: 14),
                      Tappable(
                        onTap: doRefresh,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(l.t('refresh_list'),
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: primary)),
                        ),
                      ),
                    ]),
                  ))
                // Состав класса — сгруппированный список без «аватарок»:
                // имя, почта и роль-пилюля справа.
                : CustomScrollView(
                    controller: sc,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      CupertinoSliverRefreshControl(onRefresh: doRefresh),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                        sliver: SliverToBoxAdapter(child: InsetGroup(children: [
                          for (var j = 0; j < members.length; j++) ...(() {
                            final s        = members[j];
                            final name     = (s['full_name'] ?? '').toString().trim();
                            final email    = (s['email'] ?? '').toString();
                            final role     = (s['role'] ?? '').toString();
                            final display  = name.isNotEmpty ? name : email.split('@').first;
                            final isTeacher  = role == 'teacher' || role == 'admin';
                            final roleColor  = isTeacher ? C.indigo : adaptiveText4(context);
                            final roleLabel  = isTeacher ? l.t('role_teacher_short') : l.t('role_student_short');
                            return [GroupRow(
                              pos: innerPos(j, members.length),
                              color: Colors.transparent,
                              separatorInset: 16,
                              padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                              child: Row(children: [
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(display,
                                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 1),
                                  Text(email,
                                      style: TextStyle(fontSize: 14, letterSpacing: -0.1, color: adaptiveText4(context)),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ])),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
                                  child: Text(roleLabel,
                                      style: TextStyle(fontSize: 13, color: roleColor, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                                ),
                              ]),
                            )];
                          })(),
                        ])),
                      ),
                    ],
                  )),
            ]),
          );
        },
      ),
    );
  }

  void _showRejoinableSheet(int classId, String className, Future<void> Function() onChanged) {
    final l = context.read<L10n>();
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
              Container(width: 40, height: 5, margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: adaptiveText4(context).withValues(alpha: 0.35), borderRadius: BorderRadius.circular(100))),
              Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('return_student'),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: adaptiveTextSoft(context))),
                  const SizedBox(height: 4),
                  Text('$className · ${l.t('return_student_hint')}',
                      style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context), height: 1.35)),
                ])),
              Container(height: hairline(context), color: groupSeparator(context)),
              Expanded(child: loading
                ? const Center(child: CupertinoActivityIndicator(color: C.text3))
                : candidates.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.checkmark_circle, size: 34, color: adaptiveText4(context).withValues(alpha: 0.7)),
                        const SizedBox(height: 14),
                        Text(l.t('no_archived_students'), textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, letterSpacing: -0.2, color: adaptiveText3(context), height: 1.4)),
                      ]),
                    ))
                  // Кандидаты — сгруппированным списком без «аватарок»;
                  // «Вернуть» справа акцентным текстом, как действия в
                  // системных списках.
                  : ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                      children: [InsetGroup(children: [
                        for (var i = 0; i < candidates.length; i++) ...(() {
                          final u = candidates[i] as Map<String, dynamic>;
                          final display = (u['full_name'] ?? u['email'] ?? '').toString();
                          final email = (u['email'] ?? '').toString();
                          final busy = adding.contains(u['id']);
                          return [GroupRow(
                            pos: innerPos(i, candidates.length),
                            color: Colors.transparent,
                            separatorInset: 16,
                            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                            onTap: busy ? null : () => add(u),
                            child: Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(display,
                                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: adaptiveTextSoft(context)),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 1),
                                Text(email,
                                    style: TextStyle(fontSize: 14, letterSpacing: -0.1, color: adaptiveText4(context)),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ])),
                              const SizedBox(width: 10),
                              busy
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: CupertinoActivityIndicator(radius: 9, color: adaptiveText4(context)))
                                : Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text(l.t('return_add'),
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3, color: primary))),
                            ]),
                          )];
                        })(),
                      ])],
                    )),
            ]),
          );
        });
      },
    );
  }

  Widget _classCover(dynamic coverImg, int index) {
    const grads = [[Color(0xFF006475), Color(0xFF009AAF)], [Color(0xFF7C2D12), Color(0xFFD97706)],
                   [Color(0xFF581C87), Color(0xFF9333EA)], [Color(0xFF134E4A), Color(0xFF0D9488)],
                   [Color(0xFF9D174D), Color(0xFFDB2777)]];
    final colors = grads[index % grads.length];
    if (coverImg == null) return Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight)));
    if (coverImg.toString().startsWith('data:')) {
      final bytes = decodeBase64Image(coverImg.toString());
      return bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, gaplessPlayback: true, cacheWidth: 480)
          : Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors)));
    }
    return NetworkCoverImage(url: context.read<ApiService>().fixUrl(coverImg.toString()), memCacheWidth: 480,
      errorBuilder: (_) => Container(decoration: BoxDecoration(gradient: LinearGradient(colors: colors))));
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

        // Роль — сегментированный переключатель в капсуле: выбор одного из
        // трёх взаимоисключающих значений, ровно та роль, что у нативного
        // segmented control (раньше это были три плитки с цветными рамками).
        Widget roleSegment(String value, String label, Color color) {
          final selected = role == value;
          return Expanded(child: Tappable(
            onTap: selected ? null : () async {
              final ok = await _action(u, value);
              if (ok && ctx.mounted) setS(() => u['role'] = value);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: selected ? Theme.of(ctx).colorScheme.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
                boxShadow: selected
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))]
                    : null,
              ),
              child: Center(child: Text(label,
                  style: TextStyle(fontSize: 15, fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: -0.2, color: selected ? color : adaptiveText3(ctx)))),
            ),
          ));
        }

        Widget actionRow({required IconData icon, required Color color, required String title, String? subtitle, Widget? trailing, VoidCallback? onTap, required GroupPos pos}) {
          return GroupRow(
            pos: pos,
            color: Colors.transparent,
            onTap: onTap,
            separatorInset: 62,
            padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
            child: Row(children: [
              Container(width: 32, height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 18, color: color)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4, color: color == C.red ? C.red : adaptiveTextSoft(ctx))),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 1),
                  child: Text(subtitle, style: TextStyle(fontSize: 13, height: 1.3, color: adaptiveText4(ctx)))),
              ])),
              if (trailing != null) trailing else
                Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(ctx).withValues(alpha: 0.8)),
            ]),
          );
        }

        return SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: adaptiveText4(ctx).withValues(alpha: 0.35), borderRadius: BorderRadius.circular(100)))),

            // Заголовок листа — имя и почта, без кружка с буквой.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(name,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: adaptiveTextSoft(ctx)),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (isBlocked) Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: C.red.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
                      child: Text(l.t('blocked_short'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: C.red)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text(email,
                      style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(ctx)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                const SizedBox(width: 10),
                _RoleBadge(role: role),
              ]),
            ),
            const SizedBox(height: 22),

            _SectionLabel(l.t('role')),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: adaptiveSurface2(ctx), borderRadius: BorderRadius.circular(100)),
              child: Row(children: [
                roleSegment('student', l.t('role_student_short'),  const Color(0xFF059669)),
                roleSegment('teacher', l.t('role_teacher_short'), C.indigo),
                roleSegment('admin',   l.t('role_admin_short'),   primary),
              ]),
            ),
            const SizedBox(height: 22),

            _SectionLabel(l.t('actions_label')),
            const SizedBox(height: 8),
            InsetGroup(children: [
            actionRow(
              pos: isSelf ? GroupPos.last : GroupPos.middle,
              icon: aiUnlimited ? CupertinoIcons.bolt_fill : CupertinoIcons.bolt,
              color: C.amber,
              title: l.t('ai_unlimited'),
              subtitle: aiUnlimited ? l.t('ai_unlimited_on_sub') : l.t('ai_unlimited_off_sub'),
              trailing: IgnorePointer(child: CupertinoLiquidSwitch(value: aiUnlimited, onChanged: (_) {}, accent: C.amber)),
              onTap: () async {
                final ok = await _action(u, 'toggle_ai_unlimited');
                if (ok && ctx.mounted) setS(() => u['ai_unlimited'] = !aiUnlimited);
              },
            ),
            if (!isSelf) actionRow(
              pos: GroupPos.middle,
              icon: isBlocked ? CupertinoIcons.lock_open : CupertinoIcons.nosign,
              color: isBlocked ? C.green : C.red,
              title: isBlocked ? l.t('unblock') : l.t('block'),
              subtitle: isBlocked ? l.t('unblock_sub') : l.t('block_sub'),
              onTap: () async {
                final action = isBlocked ? 'unblock' : 'block';
                if (!isBlocked) {
                  final sure = await showConfirmDialog(context,
                    title: '${l.t('block')}?',
                    message: l.t('block_user_msg'),
                    icon: CupertinoIcons.nosign, danger: true,
                    confirmText: l.t('block'), cancelText: l.t('cancel'));
                  if (sure != true) return;
                }
                final ok = await _action(u, action);
                if (ok && ctx.mounted) setS(() => u['is_active'] = isBlocked);
              },
            ),
            if (!isSelf) actionRow(
              pos: GroupPos.last,
              icon: CupertinoIcons.trash,
              color: C.red,
              title: l.t('delete'),
              subtitle: l.t('delete_user_sub'),
              onTap: () async {
                final sure = await showConfirmDialog(context,
                  title: l.t('delete_user_q'),
                  message: l.t('delete_user_msg'),
                  icon: CupertinoIcons.trash, danger: true,
                  confirmText: l.t('delete'), cancelText: l.t('cancel'));
                if (sure != true) return;
                final ok = await _action(u, 'delete');
                if (ok && ctx.mounted) Navigator.pop(ctx);
              },
            ),
            ]),
          ]),
        ));
      }),
    );
  }

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
          setS(() => error = l.t('enter_valid_email'));
          return;
        }
        if (pwCtrl.text.length < 6) {
          setS(() => error = l.t('password_min_6'));
          return;
        }
        setS(() { busy = true; error = null; });
        try {
          await context.read<ApiService>().adminCreateUser(email, pwCtrl.text, role);
          if (mounted && ctx.mounted) { Navigator.pop(ctx); showToast(context, l.t('created')); _load(); }
        } catch (_) {
          if (ctx.mounted) setS(() { busy = false; error = l.t('create_user_error'); });
        }
      }

      Widget roleChip(String value, String label, Color color) {
        final selected = role == value;
        return Expanded(child: Tappable(
          onTap: busy ? null : () => setS(() => role = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: selected ? Theme.of(ctx).colorScheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(100),
              boxShadow: selected
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))]
                  : null,
            ),
            child: Center(child: Text(label,
                style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.2, color: selected ? color : adaptiveText3(ctx)))),
          ),
        ));
      }

      return AppDialogCard(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: AppDialogIcon(icon: CupertinoIcons.person_badge_plus, color: primary)),
        const SizedBox(height: 14),
        Text(l.t('create_user'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: adaptiveTextSoft(ctx), letterSpacing: -0.4)),
        const SizedBox(height: 18),
        TextField(
          controller: emailCtrl,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: const TextStyle(fontSize: 15),
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
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: l.t('password'),
            prefixIcon: const Icon(CupertinoIcons.lock, size: 18, color: C.text4),
            suffixIcon: Tappable(
              onTap: () => setS(() => obscure = !obscure),
              label: obscure ? 'Показать пароль' : 'Скрыть пароль',
              child: Icon(obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash, size: 18, color: C.text4),
            ),
          ),
          onChanged: (_) { if (error != null) setS(() => error = null); },
          onSubmitted: (_) => submit(),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: adaptiveSurface2(ctx), borderRadius: BorderRadius.circular(100)),
          child: Row(children: [
            roleChip('student', l.t('role_student_short'),  const Color(0xFF059669)),
            roleChip('teacher', l.t('role_teacher_short'), C.indigo),
            roleChip('admin',   l.t('role_admin_short'),   primary),
          ]),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: C.red.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.tile)),
            child: Row(children: [
              const Icon(CupertinoIcons.exclamationmark_circle_fill, size: 16, color: C.red),
              const SizedBox(width: 8),
              Expanded(child: Text(error!,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: C.red))),
            ]),
          ),
        ],
        const SizedBox(height: 18),
        AppDialogActions(
          cancelText: l.t('cancel'),
          confirmText: l.t('create'),
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

/// Сводка одной карточкой с вертикальными волосяными разделителями — как итоги
/// в Apple Health. Раньше это были три самостоятельные плитки с тенями: три
/// «объекта» вместо одного факта о системе.
class _SummaryBar extends StatelessWidget {
  final List<(String value, String label)> cells;
  const _SummaryBar({required this.cells});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: groupSeparator(context), width: hairline(context)),
      ),
      child: IntrinsicHeight(child: Row(children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0)
            Container(
              width: hairline(context),
              margin: const EdgeInsets.symmetric(vertical: 12),
              color: groupSeparator(context),
            ),
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Column(children: [
              Text(cells[i].$1,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.05,
                      letterSpacing: -0.8, color: adaptiveTextSoft(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 3),
              Text(cells[i].$2, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, letterSpacing: -0.1, color: adaptiveText4(context))),
            ]),
          )),
        ],
      ])),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final color = role == 'admin' ? primary : role == 'teacher' ? C.indigo : adaptiveText4(context);
    // Роль подписана на языке интерфейса: раньше в бейдже стоял сырой ключ с
    // бэкенда («admin», «teacher») — единственное английское слово на экране.
    final label = role == 'admin'
        ? l.t('role_admin_short')
        : role == 'teacher'
            ? l.t('role_teacher_short')
            : l.t('role_student_short');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
      child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: color)),
    );
  }
}

/// Подпись над сгруппированной секцией: мелкий кегль капсом с положительным
/// трекингом — правило Apple для мелкого текста (крупный, наоборот, поджимают).
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(text.toUpperCase(),
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: adaptiveText3(context))),
  );
}

class _AiFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AiFilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tappable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          // Капсула вместо скруглённого прямоугольника и без цветного свечения:
          // фильтр — это переключатель, а не главная кнопка экрана.
          color: selected ? primary : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(100),
          border: selected ? null : Border.all(color: groupSeparator(context), width: hairline(context)),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2,
                color: selected ? Colors.white : adaptiveText2(context))),
      ),
    );
  }
}

class _ReportActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ReportActionChip({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: color)),
      ),
    );
  }
}
