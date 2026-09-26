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
import '../../widgets/app_backdrop.dart';
import '../../widgets/network_cover_image.dart';
import '../../widgets/subject_cover.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'admin_format.dart';
import 'ai_dashboard_tab.dart';
import 'class_card_sheet.dart';
import 'user_card_sheet.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminState();
}

class _AdminState extends State<AdminScreen> {
  int? _section;
  List<dynamic> _users = [];
  List<Map<String, dynamic>> _allClassPosts = [];
  List<dynamic> _aiSummary = [];
  bool _loading = true;
  bool _classesLoading = true;
  String _search = '';

  // Фильтры и сортировка списка пользователей — те же, что в веб-админке.
  String _roleFilter = 'all';
  bool _onlyBlocked = false;
  bool _onlyUnlimited = false;
  String _sort = 'tokens';

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Timer? _searchDebounce;

  Widget? _usersTabCache, _classesTabCache;
  String _usersTabSig = '', _classesTabSig = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _initAll() async {
    await Future.wait([_load(), _loadClasses(), _loadReports()]);
  }

  // ── Очередь модерации (App Store Guideline 1.2) ────────────────────────
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
    setState(() => _reports =
        _reports.where((x) => (x['id'] as num?)?.toInt() != id).toList());
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
              Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                      color: C.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(22)),
                  child: const Icon(CupertinoIcons.checkmark_shield_fill,
                      size: 32, color: C.green)),
              const SizedBox(height: 18),
              Text(l.t('no_reports'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: adaptiveTextSoft(context))),
            ]),
          ),
        ),
      ]);
    }

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: _loadReports),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, bottomBarClearance(context)),
        sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
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
            final reporter =
                (r['reporter_name'] ?? r['reporter_email'] ?? '').toString();
            final className = (r['class_name'] ?? '').toString();
            final targetTitle = (r['target_title'] ?? '').toString();
            final canDeleteContent =
                targetType == 'post' || targetType == 'assignment';

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GroupRow.card(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        // Причина жалобы — капсула; справа время, как в списках Mail.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: C.red.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(l.t(reasonKey),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.1,
                                  color: C.red)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text('${l.t(targetKey)} #${r['target_id']}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 15,
                                  letterSpacing: -0.2,
                                  color: adaptiveText4(context))),
                        ),
                        const SizedBox(width: 8),
                        Text(
                            fmtDateTimeLocal(
                                (r['created_at'] ?? '').toString()),
                            style: TextStyle(
                                fontSize: 13, color: adaptiveText4(context))),
                      ]),
                      if (className.isNotEmpty || targetTitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            if (className.isNotEmpty)
                              '${l.t('report_class_prefix')}: $className',
                            if (targetTitle.isNotEmpty) targetTitle,
                          ].join('  ·  '),
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.4,
                              color: adaptiveTextSoft(context)),
                        ),
                      ],
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(comment,
                            style: TextStyle(
                                fontSize: 15,
                                height: 1.4,
                                letterSpacing: -0.2,
                                color: adaptiveText2(context))),
                      ],
                      if (reporter.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('${l.t('report')}: $reporter',
                            style: TextStyle(
                                fontSize: 13, color: adaptiveText4(context))),
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
    if (!mounted) return;
    setState(() => _loading = true);
    final api = context.read<ApiService>();
    try {
      _users = await api.adminUsersOverview();
    } catch (e) {
      // Бэкенд без /users/overview (не обновлён) — показываем хотя бы список
      // аккаунтов, без расхода и последней активности.
      logError('AdminScreen.loadUsersOverview', e);
      try {
        _users = await api.adminUsers();
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadClasses() async {
    if (!mounted) return;
    setState(() => _classesLoading = true);
    final api = context.read<ApiService>();
    var classes = <dynamic>[];
    try {
      classes = await api.getAllClasses();
    } catch (e) {
      logError('AdminScreen.loadClasses', e);
    }
    // member_count приходит прямо со списком (/classes/all), поэтому состав
    // каждого предмета больше не догружается отдельным запросом: на 20
    // предметах это было 20 лишних обращений при каждом открытии админки.
    _allClassPosts = classes
        .map((c) => {
              ...c as Map<String, dynamic>,
              'title': c['name'],
              'teacher_name': c['teacher'],
              'user_id': c['created_by']
            })
        .toList();
    try {
      _aiSummary = await api.adminAiSummary();
    } catch (e) {
      logError('AdminScreen.loadAiSummary', e);
    }
    if (mounted) setState(() => _classesLoading = false);
  }

  /// Расход токенов по предмету — из сводки /admin/ai-usage/summary.
  (int tokens, int requests) _classUsage(int classId) {
    for (final s in _aiSummary) {
      if ((s['class_id'] as num?)?.toInt() == classId) {
        return (
          (s['total_tokens'] as num? ?? 0).toInt(),
          (s['request_count'] as num? ?? 0).toInt()
        );
      }
    }
    return (0, 0);
  }

  List<dynamic> get _filtered {
    final q = _search.trim().toLowerCase();
    final list = _users.where((u) {
      if (_roleFilter != 'all' && (u['role'] ?? 'student') != _roleFilter)
        return false;
      if (_onlyBlocked && u['is_active'] != false) return false;
      if (_onlyUnlimited && u['ai_unlimited'] != true) return false;
      if (q.isEmpty) return true;
      return (u['email'] ?? '').toString().toLowerCase().contains(q) ||
          (u['full_name'] ?? '').toString().toLowerCase().contains(q);
    }).toList();

    int tokensOf(dynamic u) => (u['total_tokens'] as num? ?? 0).toInt();
    String nameOf(dynamic u) =>
        ((u['full_name'] ?? u['email'] ?? '').toString()).toLowerCase();
    int seenOf(dynamic u) =>
        parseServerDate(u['last_active'] as String?)?.millisecondsSinceEpoch ??
        0;

    list.sort((a, b) => switch (_sort) {
          'active' => seenOf(b).compareTo(seenOf(a)),
          'name' => nameOf(a).compareTo(nameOf(b)),
          _ => tokensOf(b).compareTo(tokensOf(a)) != 0
              ? tokensOf(b).compareTo(tokensOf(a))
              : nameOf(a).compareTo(nameOf(b)),
        });
    return list;
  }

  int get _maxUserTokens {
    var max = 1;
    for (final u in _users) {
      final v = (u['total_tokens'] as num? ?? 0).toInt();
      if (v > max) max = v;
    }
    return max;
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

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final teachers = _users.where((u) => u['role'] == 'teacher').length;
    final students = _users.where((u) => u['role'] == 'student').length;
    final tabSig = '$isDark|$primary|${l.lang}';

    final page = _section == null
        ? _overviewPage(l, primary, teachers, students)
        : _sectionPage(l, primary, tabSig, _section!);

    return PopScope(
      canPop: _section == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _section != null) setState(() => _section = null);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AppBackdrop(
          child: SafeArea(
            bottom: false,
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: page,
            ),
          ),
        ),
      ),
    );
  }

  Widget _overviewPage(L10n l, Color primary, int teachers, int students) {
    return ListView(
      key: const ValueKey('admin-overview'),
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomBarClearance(context)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 0, 16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.t('admin'),
                        style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            height: 1.1,
                            color: adaptiveTextSoft(context))),
                    const SizedBox(height: 4),
                    Text(l.t('admin_sub'),
                        style: TextStyle(
                            fontSize: 15,
                            letterSpacing: -0.2,
                            color: adaptiveText3(context))),
                  ]),
            ),
            _createUserButton(l, primary),
          ]),
        ),
        _SummaryBar(cells: [
          ('${_users.length}', l.t('total_label')),
          ('$teachers', l.t('teachers_label')),
          ('$students', l.t('students_label')),
        ]),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Text(l.t('sections').toUpperCase(),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: adaptiveText3(context))),
        ),
        _AdminSectionCard(
          key: const ValueKey('admin-section-users'),
          icon: CupertinoIcons.person_2_fill,
          title: l.t('users'),
          subtitle: '${_users.length} · ${l.t('teachers_label')}: $teachers',
          accent: primary,
          onTap: () => setState(() => _section = 0),
        ),
        const SizedBox(height: 10),
        _AdminSectionCard(
          key: const ValueKey('admin-section-ai'),
          icon: CupertinoIcons.sparkles,
          title: 'AI',
          subtitle: l.t('ai_usage_section'),
          accent: C.indigo,
          onTap: () => setState(() => _section = 1),
        ),
        const SizedBox(height: 10),
        _AdminSectionCard(
          key: const ValueKey('admin-section-classes'),
          icon: CupertinoIcons.book_fill,
          title: l.t('class_tab'),
          subtitle: '${_allClassPosts.length} · ${l.t('members_label')}',
          accent: C.green,
          onTap: () => setState(() => _section = 2),
        ),
        const SizedBox(height: 10),
        _AdminSectionCard(
          key: const ValueKey('admin-section-reports'),
          icon: CupertinoIcons.flag_fill,
          title: l.t('reports_queue'),
          subtitle: _reports.isEmpty
              ? l.t('no_reports')
              : '${_reports.length} · ${l.t('reports_queue')}',
          accent: _reports.isEmpty ? adaptiveText4(context) : C.red,
          onTap: () => setState(() => _section = 3),
        ),
      ],
    );
  }

  Widget _sectionPage(L10n l, Color primary, String tabSig, int section) {
    final titles = [l.t('users'), 'AI', l.t('class_tab'), l.t('reports_queue')];
    final body = switch (section) {
      0 => _memoUsersTab(tabSig),
      1 => const AiDashboardTab(),
      2 => _memoClassesTab(tabSig),
      _ => _reportsTab(),
    };

    return Column(
      key: ValueKey('admin-section-$section'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 12, 10),
          child: Row(children: [
            Tappable(
              onTap: () => setState(() => _section = null),
              label: 'Назад',
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(CupertinoIcons.chevron_left, size: 21),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Text(titles[section],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.7,
                      color: adaptiveTextSoft(context))),
            ),
            if (section == 0) _createUserButton(l, primary),
            if (section == 3)
              Tappable(
                onTap: _reportsLoading ? null : _loadReports,
                label: l.t('refresh'),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: _reportsLoading
                        ? const CupertinoActivityIndicator(radius: 9)
                        : Icon(CupertinoIcons.arrow_clockwise,
                            size: 19, color: primary),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(child: body),
      ],
    );
  }

  Widget _createUserButton(L10n l, Color primary) => Tappable(
        onTap: _showCreateDialog,
        label: l.t('add'),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(CupertinoIcons.person_badge_plus, color: primary, size: 19),
            const SizedBox(width: 7),
            Text(l.t('add'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: primary)),
          ]),
        ),
      );

  Widget _memoUsersTab(String tl) {
    final sig = 'u|$_loading|${identityHashCode(_users)}|$_search|$_roleFilter'
        '|$_onlyBlocked|$_onlyUnlimited|$_sort|$tl';
    if (sig != _usersTabSig || _usersTabCache == null) {
      _usersTabSig = sig;
      _usersTabCache = _usersTab();
    }
    return _usersTabCache!;
  }

  Widget _memoClassesTab(String tl) {
    final sig = 'c|$_classesLoading|${identityHashCode(_allClassPosts)}'
        '|${identityHashCode(_aiSummary)}|${identityHashCode(_users)}|$tl';
    if (sig != _classesTabSig || _classesTabCache == null) {
      _classesTabSig = sig;
      _classesTabCache = _classesTab();
    }
    return _classesTabCache!;
  }

  Widget _usersTab() {
    final l = context.read<L10n>();
    final filtered = _filtered;
    final maxTokens = _maxUserTokens;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: CupertinoSearchTextField(
          placeholder: l.t('search_users'),
          backgroundColor: adaptiveSurface2(context),
          style: TextStyle(
              fontSize: 16,
              letterSpacing: -0.3,
              color: adaptiveTextSoft(context)),
          placeholderStyle: TextStyle(
              fontSize: 16, letterSpacing: -0.3, color: adaptiveText4(context)),
          itemColor: adaptiveText4(context),
          onChanged: (v) {
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() => _search = v);
            });
          },
        ),
      ),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _filterChip(l.t('filter_all'), _roleFilter == 'all',
                _roleCount('all'), () => setState(() => _roleFilter = 'all')),
            _filterChip(
                l.t('students_label'),
                _roleFilter == 'student',
                _roleCount('student'),
                () => setState(() => _roleFilter = 'student')),
            _filterChip(
                l.t('teachers_label'),
                _roleFilter == 'teacher',
                _roleCount('teacher'),
                () => setState(() => _roleFilter = 'teacher')),
            _filterChip(
                l.t('role_admin_short'),
                _roleFilter == 'admin',
                _roleCount('admin'),
                () => setState(() => _roleFilter = 'admin')),
            Container(
                width: hairline(context),
                height: 18,
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: groupSeparator(context)),
            _filterChip(l.t('blocked_short'), _onlyBlocked, _blockedCount,
                () => setState(() => _onlyBlocked = !_onlyBlocked)),
            _filterChip(l.t('ai_unlimited'), _onlyUnlimited, _unlimitedCount,
                () => setState(() => _onlyUnlimited = !_onlyUnlimited)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 8),
        child: Row(children: [
          Expanded(
            child: Text('${filtered.length} ${l.t('of_word')} ${_users.length}',
                style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
          ),
          Tappable(
            onTap: _showSortSheet,
            label: l.t('sort_label'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.arrow_up_arrow_down,
                    size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(_sortLabel(l),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(
                child: CupertinoActivityIndicator(radius: 13, color: C.text3))
            : filtered.isEmpty
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
                    child: Text(l.t('nobody_found'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.3,
                            color: adaptiveText4(context))),
                  ))
                : CustomScrollView(slivers: [
                    CupertinoSliverRefreshControl(onRefresh: _load),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          16, 0, 16, bottomBarClearance(context)),
                      sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                        childCount: filtered.length,
                        (ctx, i) => Entrance(
                          key: ValueKey(filtered[i]['id']),
                          index: i,
                          child: RepaintBoundary(
                              child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _userRow(l,
                                filtered[i] as Map<String, dynamic>, maxTokens),
                          )),
                        ),
                      )),
                    ),
                  ]),
      ),
    ]);
  }

  int _roleCount(String role) => role == 'all'
      ? _users.length
      : _users.where((u) => (u['role'] ?? 'student') == role).length;
  int get _blockedCount => _users.where((u) => u['is_active'] == false).length;
  int get _unlimitedCount =>
      _users.where((u) => u['ai_unlimited'] == true).length;

  String _sortLabel(L10n l) => switch (_sort) {
        'active' => l.t('sort_by_activity'),
        'name' => l.t('sort_by_name'),
        _ => l.t('sort_by_tokens'),
      };

  void _showSortSheet() {
    final l = context.read<L10n>();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l.t('sort_label')),
        actions: [
          for (final option in const ['tokens', 'active', 'name'])
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                if (_sort != option) setState(() => _sort = option);
              },
              child: Text(switch (option) {
                'active' => l.t('sort_by_activity'),
                'name' => l.t('sort_by_name'),
                _ => l.t('sort_by_tokens'),
              }),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.t('cancel')),
        ),
      ),
    );
  }

  Widget _filterChip(
      String label, bool selected, int count, VoidCallback onTap) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tappable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.13)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? null
                : Border.all(
                    color: groupSeparator(context), width: hairline(context)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.2,
                    color: selected ? primary : adaptiveText2(context))),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text('$count',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: selected ? primary : adaptiveText4(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _userRow(L10n l, Map<String, dynamic> u, int maxTokens) {
    final id = (u['id'] as num?)?.toInt() ?? 0;
    final name = (u['full_name'] ?? '').toString().trim().isNotEmpty
        ? u['full_name'].toString()
        : (u['email'] ?? '').toString().split('@').first;
    final role = (u['role'] ?? 'student').toString();
    final blocked = u['is_active'] == false;
    final unlimited = u['ai_unlimited'] == true;
    final unverified = u['is_verified'] == false;
    final tokens = (u['total_tokens'] as num? ?? 0).toInt();
    final classCount = (u['class_count'] as num? ?? 0).toInt();

    return GroupRow.card(
      onTap: () => _openUserCard(u),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          InitialsAvatar(id: id, name: name, size: 40, radius: 13),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.4,
                              color: adaptiveTextSoft(context)))),
                  if (blocked)
                    _tag(l.t('blocked_short'), C.red)
                  else if (unverified)
                    _tag(l.t('email_unverified_short'), C.amber),
                  if (unlimited)
                    _tag(l.t('ai_unlimited_tag'),
                        Theme.of(context).colorScheme.primary),
                ]),
                const SizedBox(height: 2),
                Text((u['email'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        letterSpacing: -0.2,
                        color: adaptiveText4(context))),
              ])),
          const SizedBox(width: 10),
          _RoleBadge(role: role),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: MiniBar(
            value: tokens > 0 ? tokens / maxTokens : 0,
            color: Theme.of(context).colorScheme.primary,
            height: 5,
          )),
          const SizedBox(width: 10),
          Text(fmtInt(tokens),
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: adaptiveText2(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 5),
        Text(
          [
            l.t('tokens').toLowerCase(),
            if (classCount > 0) '$classCount ${l.t('subjects_short')}',
            fmtRelativeDate(u['last_active'] as String?, l),
          ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: adaptiveText4(context)),
        ),
      ]),
    );
  }

  Widget _tag(String text, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(7)),
        child: Text(text,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );

  Future<void> _openUserCard(Map<String, dynamic> u) async {
    final isSelf =
        (u['id'] as num?)?.toInt() == context.read<AuthProvider>().userId;
    await showUserCardSheet(
      context,
      row: u,
      isSelf: isSelf,
      onAction: (action) => _action(u, action),
      onDeleted: () {
        if (!mounted) return;
        setState(
            () => _users = _users.where((x) => x['id'] != u['id']).toList());
      },
    );
    // Карточка могла поменять роль/блокировку/безлимит — список перечитываем,
    // чтобы строка и агрегаты соответствовали новому состоянию.
    if (mounted) _load();
  }

  Widget _classesTab() {
    final l = context.read<L10n>();
    if (_classesLoading && _allClassPosts.isEmpty) {
      return const Center(
          child: CupertinoActivityIndicator(radius: 13, color: C.text3));
    }

    final classes = _allClassPosts;
    final userNames = _userNameMap;

    if (classes.isEmpty) {
      final primary = Theme.of(context).colorScheme.primary;
      return Center(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(22)),
              child: Icon(CupertinoIcons.book_fill, size: 32, color: primary)),
          const SizedBox(height: 18),
          Text(l.t('no_classes_admin'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: adaptiveTextSoft(context))),
        ]),
      ));
    }

    // Самый «дорогой» предмет задаёт масштаб полосы: в списке важно, кто
    // выделяется, а не сколько процентов у каждого.
    var maxTokens = 1;
    for (final c in classes) {
      final v = _classUsage((c['id'] as num?)?.toInt() ?? 0).$1;
      if (v > maxTokens) maxTokens = v;
    }

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: () async {
        await _load();
        await _loadClasses();
      }),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottomBarClearance(context)),
        sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
          childCount: classes.length,
          (ctx, i) {
            final cls = classes[i];
            final classId = (cls['id'] as num?)?.toInt() ?? 0;
            final title = cls['title']?.toString() ?? '';
            final coverImg = cardCoverUrl(cls);
            final uid = (cls['user_id'] as num?)?.toInt();
            final teacherName = (cls['teacher_name'] ?? '').toString().trim();
            final creatorName = teacherName.isNotEmpty
                ? teacherName
                : uid != null
                    ? (userNames[uid] ?? '#$uid')
                    : '—';
            final members = (cls['member_count'] as num? ?? 0).toInt();
            final usage = _classUsage(classId);

            return Entrance(
              key: ValueKey(cls['id']),
              index: i,
              child: RepaintBoundary(
                  child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: GroupRow.card(
                  onTap: () => _openClassCard(cls),
                  padding: EdgeInsets.zero,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            height: 92,
                            width: double.infinity,
                            child: Stack(fit: StackFit.expand, children: [
                              _classCover(coverImg, i,
                                  icon: cls['cover_icon'] as String?,
                                  color: cls['cover_color'] as String?,
                                  coverSource: cls['cover_source'] as String?,
                                  iconSize: 38),
                              Positioned.fill(
                                  child: DecoratedBox(
                                      decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                stops: const [0.55, 1.0],
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45)
                                ],
                              )))),
                              Positioned(
                                  top: 10,
                                  right: 10,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                          sigmaX: 12, sigmaY: 12),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 5),
                                        color: Colors.black
                                            .withValues(alpha: 0.28),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                  CupertinoIcons.person_2_fill,
                                                  size: 13,
                                                  color: Colors.white),
                                              const SizedBox(width: 5),
                                              Text('$members',
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Colors.white,
                                                      fontFeatures: [
                                                        FontFeature
                                                            .tabularFigures()
                                                      ])),
                                            ]),
                                      ),
                                    ),
                                  )),
                            ])),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title,
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: -0.5,
                                          height: 1.15,
                                          color: adaptiveTextSoft(context)),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    Icon(CupertinoIcons.person,
                                        size: 13,
                                        color: adaptiveText4(context)),
                                    const SizedBox(width: 5),
                                    Expanded(
                                        child: Text(creatorName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 14,
                                                letterSpacing: -0.2,
                                                color:
                                                    adaptiveText4(context)))),
                                  ]),
                                  const SizedBox(height: 12),
                                  // Три числа предмета в ряд — как итоги в системных карточках.
                                  Row(children: [
                                    _classMetric(fmtCompact(usage.$1, l),
                                        l.t('tokens').toLowerCase()),
                                    _metricDivider(),
                                    _classMetric(fmtInt(usage.$2),
                                        l.t('requests_short')),
                                    _metricDivider(),
                                    _classMetric(fmtInt(members),
                                        l.t('members_label').toLowerCase()),
                                  ]),
                                  const SizedBox(height: 11),
                                  MiniBar(
                                    value:
                                        usage.$1 > 0 ? usage.$1 / maxTokens : 0,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    height: 4,
                                  ),
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

  Widget _classMetric(String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: adaptiveTextSoft(context),
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
        ]),
      );

  Widget _metricDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: groupSeparator(context),
      );

  Future<void> _openClassCard(Map<String, dynamic> cls) async {
    final classId = (cls['id'] as num?)?.toInt();
    if (classId == null) return;
    await showClassCardSheet(
      context,
      classId: classId,
      name: cls['title']?.toString() ?? '',
      coverIcon: cls['cover_icon'] as String?,
      coverColor: cls['cover_color'] as String?,
    );
    // В карточке можно вернуть студента — состав и счётчики могли измениться.
    if (mounted) _loadClasses();
  }

  Widget _classCover(dynamic coverImg, int index,
      {String? icon,
      String? color,
      String? coverSource,
      double iconSize = 40}) {
    const grads = [
      [Color(0xFF006475), Color(0xFF009AAF)],
      [Color(0xFF7C2D12), Color(0xFFD97706)],
      [Color(0xFF581C87), Color(0xFF9333EA)],
      [Color(0xFF134E4A), Color(0xFF0D9488)],
      [Color(0xFF9D174D), Color(0xFFDB2777)]
    ];
    final colors = grads[index % grads.length];
    if (coverImg == null) {
      return Stack(fit: StackFit.expand, children: [
        Container(
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight))),
        SubjectIconOverlay(icon: icon, color: color, size: iconSize),
      ]);
    }
    final Widget background;
    if (coverImg.toString().startsWith('data:')) {
      final bytes = decodeBase64Image(coverImg.toString());
      background = bytes != null
          ? Image.memory(bytes,
              fit: BoxFit.cover,
              width: double.infinity,
              gaplessPlayback: true,
              cacheWidth: 480)
          : Container(
              decoration:
                  BoxDecoration(gradient: LinearGradient(colors: colors)));
    } else {
      background = NetworkCoverImage(
          url: context.read<ApiService>().fixUrl(coverImg.toString()),
          memCacheWidth: 480,
          errorBuilder: (_) => Container(
              decoration:
                  BoxDecoration(gradient: LinearGradient(colors: colors))));
    }
    return Stack(fit: StackFit.expand, children: [
      background,
      if (coverSource != 'ai_hero')
        SubjectIconOverlay(icon: icon, color: color, size: iconSize),
    ]);
  }

  Future<bool> _action(dynamic u, String action) async {
    final api = context.read<ApiService>();
    if (u['id'] == context.read<AuthProvider>().userId &&
        ['block', 'delete'].contains(action)) return false;
    try {
      switch (action) {
        case 'student':
        case 'teacher':
        case 'admin':
          await api.adminSetRole(u['id'], action);
          break;
        case 'block':
          await api.adminBlock(u['id']);
          break;
        case 'unblock':
          await api.adminUnblock(u['id']);
          break;
        case 'delete':
          await api.adminDelete(u['id']);
          break;
        case 'toggle_ai_unlimited':
          await api.adminSetAiUnlimited(u['id'], u['ai_unlimited'] != true);
          break;
      }
      if (mounted) {
        showToast(context, context.read<L10n>().t('done'));
        _load();
      }
      return true;
    } catch (_) {
      if (mounted)
        showToast(context, context.read<L10n>().t('error'), error: true);
      return false;
    }
  }

  void _showCreateDialog() {
    final emailCtrl = TextEditingController(), pwCtrl = TextEditingController();
    String role = 'student';
    String? error;
    bool busy = false, obscure = true;
    final l = context.read<L10n>();

    showAppDialog(context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
              final primary = Theme.of(ctx).colorScheme.primary;

              Future<void> submit() async {
                final email = emailCtrl.text.trim();
                if (email.isEmpty ||
                    !email.contains('@') ||
                    !email.contains('.')) {
                  setS(() => error = l.t('enter_valid_email'));
                  return;
                }
                if (pwCtrl.text.length < 6) {
                  setS(() => error = l.t('password_min_6'));
                  return;
                }
                setS(() {
                  busy = true;
                  error = null;
                });
                try {
                  await context
                      .read<ApiService>()
                      .adminCreateUser(email, pwCtrl.text, role);
                  if (mounted && ctx.mounted) {
                    Navigator.pop(ctx);
                    showToast(context, l.t('created'));
                    _load();
                  }
                } catch (_) {
                  if (ctx.mounted)
                    setS(() {
                      busy = false;
                      error = l.t('create_user_error');
                    });
                }
              }

              Widget roleChip(String value, String label, Color color) {
                final selected = role == value;
                return Expanded(
                    child: Tappable(
                  onTap: busy ? null : () => setS(() => role = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(ctx).colorScheme.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1))
                            ]
                          : null,
                    ),
                    child: Center(
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                letterSpacing: -0.2,
                                color: selected ? color : adaptiveText3(ctx)))),
                  ),
                ));
              }

              return AppDialogCard(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Center(
                        child: AppDialogIcon(
                            icon: CupertinoIcons.person_badge_plus,
                            color: primary)),
                    const SizedBox(height: 14),
                    Text(l.t('create_user'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: adaptiveTextSoft(ctx),
                            letterSpacing: -0.4)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: emailCtrl,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Email',
                        prefixIcon:
                            Icon(CupertinoIcons.mail, size: 18, color: C.text4),
                      ),
                      onChanged: (_) {
                        if (error != null) setS(() => error = null);
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: pwCtrl,
                      enabled: !busy,
                      obscureText: obscure,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: l.t('password'),
                        prefixIcon: const Icon(CupertinoIcons.lock,
                            size: 18, color: C.text4),
                        suffixIcon: Tappable(
                          onTap: () => setS(() => obscure = !obscure),
                          label: obscure ? 'Показать пароль' : 'Скрыть пароль',
                          child: Icon(
                              obscure
                                  ? CupertinoIcons.eye
                                  : CupertinoIcons.eye_slash,
                              size: 18,
                              color: C.text4),
                        ),
                      ),
                      onChanged: (_) {
                        if (error != null) setS(() => error = null);
                      },
                      onSubmitted: (_) => submit(),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                          color: adaptiveSurface2(ctx),
                          borderRadius: BorderRadius.circular(13)),
                      child: Row(children: [
                        roleChip('student', l.t('role_student_short'),
                            const Color(0xFF059669)),
                        roleChip(
                            'teacher', l.t('role_teacher_short'), C.indigo),
                        roleChip('admin', l.t('role_admin_short'), primary),
                      ]),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                            color: C.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadii.tile)),
                        child: Row(children: [
                          const Icon(CupertinoIcons.exclamationmark_circle_fill,
                              size: 16, color: C.red),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(error!,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -0.2,
                                      color: C.red))),
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
      Future.delayed(const Duration(seconds: 1), () {
        emailCtrl.dispose();
        pwCtrl.dispose();
      });
    });
  }
}

class _AdminSectionCard extends StatelessWidget {
  const _AdminSectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tappable(
      onTap: onTap,
      label: title,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
              color: groupSeparator(context), width: hairline(context)),
          boxShadow: softShadow(isDark),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 13),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: adaptiveTextSoft(context))),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      letterSpacing: -0.1,
                      color: adaptiveText4(context))),
            ]),
          ),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.chevron_right,
              size: 15, color: adaptiveText4(context)),
        ]),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final List<(String value, String label)> cells;
  const _SummaryBar({required this.cells});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final icons = <IconData>[
      CupertinoIcons.person_2_fill,
      CupertinoIcons.person_crop_rectangle_fill,
      CupertinoIcons.person_fill,
    ];
    return Row(children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 11),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: groupSeparator(context), width: hairline(context)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icons[i.clamp(0, icons.length - 1)],
                  size: 16, color: primary),
              const SizedBox(height: 9),
              Text(cells[i].$1,
                  style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      letterSpacing: -0.8,
                      color: adaptiveTextSoft(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 4),
              Text(cells[i].$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      color: adaptiveText4(context))),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final color = role == 'admin'
        ? primary
        : role == 'teacher'
            ? C.indigo
            : adaptiveText4(context);
    final label = role == 'admin'
        ? l.t('role_admin_short')
        : role == 'teacher'
            ? l.t('role_teacher_short')
            : l.t('role_student_short');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: color)),
    );
  }
}

class _ReportActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ReportActionChip(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tappable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: color)),
      ),
    );
  }
}
