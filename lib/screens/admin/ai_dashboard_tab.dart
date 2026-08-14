import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dates.dart';
import '../../utils/errors.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/tappable.dart';
import 'admin_format.dart';

/// Дашборд расхода токенов: куда именно уходят токены (чат, проверка работ,
/// обложки, названия чатов), как расход шёл по дням, какие предметы и люди
/// тратят больше всех, и журнал запросов с фильтром по виду расхода.
///
/// Всё считает бэкенд (`/admin/ai-usage/dashboard`) — экран только рисует,
/// поэтому цифры совпадают с веб-админкой до единицы.
class AiDashboardTab extends StatefulWidget {
  const AiDashboardTab({super.key});

  @override
  State<AiDashboardTab> createState() => _AiDashboardTabState();
}

class _AiDashboardTabState extends State<AiDashboardTab> {
  static const _periods = [7, 30, 90, 365];
  static const _pageSize = 30;

  int _days = 30;
  Map<String, dynamic>? _data;
  bool _loading = true;

  List<dynamic> _logs = [];
  int _logTotal = 0;
  int _logPage = 1;
  bool _logLoading = true;
  bool _logMoreLoading = false;

  /// Активный фильтр журнала: список endpoint'ов через запятую (вид расхода).
  String? _kindFilter;
  String _kindFilterLabel = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadDashboard(), _loadLogs()]);
  }

  Future<void> _loadDashboard() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      _data = await context.read<ApiService>().adminAiDashboard(days: _days);
    } catch (e) {
      logError('AdminAiDashboard.load', e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _logLoading = true);
    try {
      final page = await context.read<ApiService>().adminAiUsagePage(
            days: _days,
            endpoint: _kindFilter,
            page: 1,
            pageSize: _pageSize,
          );
      _logs = List<dynamic>.from(page['items'] as List? ?? const []);
      _logTotal = (page['total'] as num?)?.toInt() ?? _logs.length;
      _logPage = 1;
    } catch (e) {
      logError('AdminAiDashboard.logs', e);
    }
    if (mounted) setState(() => _logLoading = false);
  }

  Future<void> _loadMoreLogs() async {
    if (_logMoreLoading || _logs.length >= _logTotal) return;
    setState(() => _logMoreLoading = true);
    try {
      final page = await context.read<ApiService>().adminAiUsagePage(
            days: _days,
            endpoint: _kindFilter,
            page: _logPage + 1,
            pageSize: _pageSize,
          );
      final items = List<dynamic>.from(page['items'] as List? ?? const []);
      if (mounted) {
        setState(() {
          _logs.addAll(items);
          _logPage++;
        });
      }
    } catch (e) {
      logError('AdminAiDashboard.loadMore', e);
    }
    if (mounted) setState(() => _logMoreLoading = false);
  }

  void _setPeriod(int days) {
    if (_days == days) return;
    setState(() => _days = days);
    _loadAll();
  }

  /// Клик по виду расхода фильтрует журнал; повторный — снимает фильтр.
  void _toggleKind(String endpoints, String label) {
    setState(() {
      if (_kindFilter == endpoints) {
        _kindFilter = null;
      } else {
        _kindFilter = endpoints;
        _kindFilterLabel = label;
      }
    });
    _loadLogs();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    if (_loading && _data == null) {
      return const Center(child: CupertinoActivityIndicator(radius: 13, color: C.text3));
    }
    final d = _data;
    if (d == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(l.t('card_load_error'),
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: adaptiveText3(context))),
        ),
      );
    }

    final totals = (d['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final allTime = (d['totals_all_time'] as Map?)?.cast<String, dynamic>() ?? const {};
    final groups = List<Map<String, dynamic>>.from(
        ((d['by_group'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()));
    groups.sort((a, b) => ((b['total_tokens'] as num? ?? 0)).compareTo(a['total_tokens'] as num? ?? 0));
    final byDay = (d['by_day'] as List?) ?? const [];
    final byClass = (d['by_class'] as List?) ?? const [];
    final topUsers = (d['top_users'] as List?) ?? const [];
    final limits = (d['limits'] as Map?)?.cast<String, dynamic>() ?? const {};
    final total = (totals['total_tokens'] as num? ?? 0).toInt();

    return CustomScrollView(slivers: [
      CupertinoSliverRefreshControl(onRefresh: _loadAll),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, bottomBarClearance(context)),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            _periodControl(l),
            const SizedBox(height: 14),
            _heroCard(l, totals, allTime),
            const SizedBox(height: 14),
            _budgetCard(l, limits),
            const SizedBox(height: 22),

            _SectionLabel(l.t('where_tokens_go')),
            const SizedBox(height: 8),
            if (groups.isEmpty)
              _emptyBlock(l.t('no_ai_data'))
            else ...[
              for (var i = 0; i < groups.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _kindCard(l, groups[i], total),
              ],
            ],

            if (byDay.isNotEmpty) ...[
              const SizedBox(height: 22),
              _SectionLabel(l.t('daily_usage')),
              const SizedBox(height: 8),
              _DailyChart(days: byDay, groups: groups, endpointGroups: _endpointGroups(d)),
            ],

            if (byClass.isNotEmpty) ...[
              const SizedBox(height: 22),
              _SectionLabel(l.t('by_classes')),
              const SizedBox(height: 8),
              _rankList(l, byClass, isClass: true),
            ],

            if (topUsers.isNotEmpty) ...[
              const SizedBox(height: 22),
              _SectionLabel(l.t('by_users')),
              const SizedBox(height: 8),
              _rankList(l, topUsers, isClass: false),
            ],

            const SizedBox(height: 22),
            _SectionLabel('${l.t('detail_log')} · ${fmtInt(_logTotal)}'),
            const SizedBox(height: 8),
            if (_kindFilter != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Tappable(
                  onTap: () => _toggleKind(_kindFilter!, _kindFilterLabel),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_kindFilterLabel,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 6),
                      Icon(CupertinoIcons.xmark, size: 12, color: Theme.of(context).colorScheme.primary),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            _logList(l),
          ]),
        ),
      ),
    ]);
  }

  /// endpoint → group: журнал приходит с endpoint'ом, а цвет закреплён за
  /// семейством функций.
  Map<String, String> _endpointGroups(Map<String, dynamic> d) {
    final map = <String, String>{};
    for (final e in (d['by_endpoint'] as List?) ?? const []) {
      final m = e as Map;
      map[(m['endpoint'] ?? '').toString()] = (m['group'] ?? 'other').toString();
    }
    return map;
  }

  Widget _periodControl(L10n l) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(100)),
      child: Row(children: [
        for (final p in _periods)
          Expanded(
            child: Tappable(
              onTap: () => _setPeriod(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _days == p ? Theme.of(context).colorScheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  boxShadow: _days == p
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 3, offset: const Offset(0, 1))]
                      : null,
                ),
                child: Center(
                  child: Text(_periodLabel(l, p),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: _days == p ? FontWeight.w600 : FontWeight.w500,
                          letterSpacing: -0.2,
                          color: _days == p ? adaptiveText1(context) : adaptiveText3(context))),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  String _periodLabel(L10n l, int days) => switch (days) {
    7 => '7 ${l.t('period_days')}',
    30 => '30 ${l.t('period_days')}',
    90 => '3 ${l.t('period_months')}',
    _ => l.t('year_short'),
  };

  Widget _heroCard(L10n l, Map<String, dynamic> totals, Map<String, dynamic> allTime) {
    final primary = Theme.of(context).colorScheme.primary;
    final requests = (totals['request_count'] as num? ?? 0).toInt();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.secondary, primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(l.t('tokens_for_period').toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.7, color: Colors.white70)),
          ),
          Tappable(
            onTap: _loadAll,
            label: l.t('refresh'),
            child: SizedBox(
                width: 40,
                height: 32,
                child: Icon(CupertinoIcons.arrow_counterclockwise,
                    size: 18, color: Colors.white.withValues(alpha: 0.9))),
          ),
        ]),
        Text(fmtInt(totals['total_tokens']),
            style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                height: 1.05,
                letterSpacing: -1.2,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()])),
        const SizedBox(height: 4),
        Text('${l.t('all_time_label')}: ${fmtInt(allTime['total_tokens'])}',
            style: const TextStyle(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 14),
        Row(children: [
          _heroStat(fmtInt(requests), l.t('requests_label')),
          _heroDivider(),
          _heroStat(fmtInt(totals['avg_tokens']), l.t('avg_per_request')),
          _heroDivider(),
          _heroStat(fmtInt(totals['user_count']), l.t('active_users_label')),
        ]),
        const SizedBox(height: 12),
      ]),
    );
  }

  Widget _heroStat(String value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()])),
          Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.2, color: Colors.white70)),
        ]),
      );

  Widget _heroDivider() => Container(
        width: 1,
        height: 30,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: Colors.white.withValues(alpha: 0.22),
      );

  Widget _budgetCard(L10n l, Map<String, dynamic> limits) {
    final budget = (limits['daily_token_budget'] as num? ?? 0).toInt();
    final used = (limits['tokens_used_today'] as num? ?? 0).toInt();
    final messageLimit = (limits['daily_message_limit'] as num? ?? 0).toInt();
    final pct = budget > 0 ? (used / budget).clamp(0.0, 1.0) : 0.0;
    final color = pct >= 0.9 ? C.red : pct >= 0.7 ? C.amber : Theme.of(context).colorScheme.primary;
    final pctText = budget <= 0
        ? '—'
        : pct > 0 && pct < 0.01
            ? '<1%'
            : '${(pct * 100).round()}%';

    return GroupRow.card(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(l.t('daily_budget'),
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: adaptiveTextSoft(context))),
          ),
          Text(pctText,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 10),
        MiniBar(value: pct, color: color, height: 8),
        const SizedBox(height: 8),
        Text(
          budget > 0
              ? '${l.t('today_spent')}: ${fmtInt(used)} ${l.t('of_word')} ${fmtInt(budget)}'
              : '${l.t('today_spent')}: ${fmtInt(used)} · ${l.t('budget_off')}',
          style: TextStyle(fontSize: 13, color: adaptiveText4(context)),
        ),
        Text('${l.t('message_limit_label')}: ${messageLimit > 0 ? messageLimit : '∞'}',
            style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
      ]),
    );
  }

  Widget _kindCard(L10n l, Map<String, dynamic> g, int total) {
    final group = (g['group'] ?? 'other').toString();
    final color = kindColor(context, group);
    final tokens = (g['total_tokens'] as num? ?? 0).toInt();
    final requests = (g['request_count'] as num? ?? 0).toInt();
    final share = total > 0 ? tokens / total : 0.0;
    final endpoints = List<String>.from((g['endpoints'] as List?) ?? const []);
    endpoints.sort();
    final key = endpoints.join(',');
    final selected = _kindFilter == key;

    return GroupRow.card(
      onTap: () => _toggleKind(key, (g['label'] ?? '').toString()),
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(kindIcon(group), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((g['label'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: adaptiveTextSoft(context))),
              Text('${fmtInt(requests)} ${l.t('requests_short')} · ~${fmtInt(tokens / (requests == 0 ? 1 : requests))} ${l.t('per_request_short')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
            ]),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtInt(tokens),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    color: adaptiveTextSoft(context),
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Text('${(share * 100).toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
          ]),
        ]),
        const SizedBox(height: 11),
        MiniBar(value: share, color: color, height: 6),
        if (selected) ...[
          const SizedBox(height: 9),
          Text(l.t('filter_applied_to_log'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ]),
    );
  }

  Widget _rankList(L10n l, List<dynamic> rows, {required bool isClass}) {
    final maxTokens = rows.fold<int>(1, (m, r) {
      final v = ((r as Map)['total_tokens'] as num? ?? 0).toInt();
      return v > m ? v : m;
    });
    return InsetGroup(children: [
      for (var i = 0; i < rows.length; i++)
        _rankRow(l, (rows[i] as Map).cast<String, dynamic>(), maxTokens, innerPos(i, rows.length), isClass, i),
    ]);
  }

  Widget _rankRow(L10n l, Map<String, dynamic> r, int maxTokens, GroupPos pos, bool isClass, int index) {
    final tokens = (r['total_tokens'] as num? ?? 0).toInt();
    final requests = (r['request_count'] as num? ?? 0).toInt();
    final primary = Theme.of(context).colorScheme.primary;
    final String title;
    Widget leading;
    if (isClass) {
      final classId = (r['class_id'] as num?)?.toInt();
      title = (r['class_name'] ?? '').toString().isNotEmpty
          ? r['class_name'].toString()
          : classId == null
              ? l.t('no_class_label')
              : '${l.t('class_col')} #$classId';
      leading = Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
        child: Text('${index + 1}',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: adaptiveText4(context),
                fontFeatures: const [FontFeature.tabularFigures()])),
      );
    } else {
      final uid = (r['user_id'] as num?)?.toInt() ?? 0;
      title = (r['name'] ?? r['email'] ?? '#$uid').toString();
      leading = InitialsAvatar(id: uid, name: title, size: 30, radius: 10);
    }

    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 16,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(children: [
        leading,
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                        color: adaptiveTextSoft(context))),
              ),
              const SizedBox(width: 10),
              Text(fmtInt(tokens),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: adaptiveTextSoft(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 6),
            MiniBar(value: tokens / maxTokens, color: primary, height: 5),
            const SizedBox(height: 5),
            Text('${fmtInt(requests)} ${l.t('requests_short')}',
                style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
          ]),
        ),
      ]),
    );
  }

  Widget _logList(L10n l) {
    if (_logLoading && _logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CupertinoActivityIndicator(radius: 11)),
      );
    }
    if (_logs.isEmpty) return _emptyBlock(l.t('no_records'));

    final groups = _endpointGroups(_data ?? const {});
    return InsetGroup(children: [
      for (var i = 0; i < _logs.length; i++)
        _logRow(l, (_logs[i] as Map).cast<String, dynamic>(), groups,
            (i == _logs.length - 1 && _logs.length >= _logTotal) ? GroupPos.last : GroupPos.middle),
      if (_logs.length < _logTotal)
        GroupRow(
          pos: GroupPos.last,
          color: Colors.transparent,
          onTap: _logMoreLoading ? null : _loadMoreLogs,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Center(
            child: _logMoreLoading
                ? CupertinoActivityIndicator(radius: 9, color: adaptiveText4(context))
                : Text(l.t('show_more_full'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.primary)),
          ),
        ),
    ]);
  }

  Widget _logRow(L10n l, Map<String, dynamic> item, Map<String, String> groups, GroupPos pos) {
    final endpoint = (item['endpoint'] ?? '').toString();
    final color = kindColor(context, groups[endpoint] ?? 'other');
    final userName = (item['user_name'] ?? item['user_email'] ?? '').toString();
    final className = (item['class_name'] ?? '').toString();
    final date = parseServerDate(item['created_at'] as String?)?.toLocal();
    final dateText = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')} '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return GroupRow(
      pos: pos,
      color: Colors.transparent,
      separatorInset: 16,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((item['label'] ?? endpoint).toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: adaptiveTextSoft(context))),
            const SizedBox(height: 1),
            Text(
              [
                if (userName.isNotEmpty) userName,
                if (className.isNotEmpty) className else l.t('no_class_label'),
                if (dateText.isNotEmpty) dateText,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: adaptiveText4(context)),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(fmtInt(item['total_tokens']),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: adaptiveTextSoft(context),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text('${fmtInt(item['prompt_tokens'])}+${fmtInt(item['completion_tokens'])}',
              style: TextStyle(fontSize: 12, color: adaptiveText4(context))),
        ]),
      ]),
    );
  }

  Widget _emptyBlock(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(
          child: Text(text, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: adaptiveText4(context))),
        ),
      );
}

/// Столбики расхода по дням, сложенные по видам запросов. С 92 дней период
/// укрупняется до недель: 365 столбиков шириной в волосок ничего не показывают.
class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days, required this.groups, required this.endpointGroups});

  final List<dynamic> days;
  final List<Map<String, dynamic>> groups;
  final Map<String, String> endpointGroups;

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final buckets = _buckets();
    if (buckets.isEmpty) return const SizedBox.shrink();
    final peak = buckets.fold<int>(1, (m, b) => b.total > m ? b.total : m);
    final bounds = _logBounds(buckets);
    final order = groups.map((g) => (g['group'] ?? 'other').toString()).toList();
    final weekly = days.length > 92;

    return GroupRow.card(
      key: const ValueKey('daily-chart'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(weekly ? l.t('by_weeks') : l.t('by_days'),
                style: TextStyle(fontSize: 13, letterSpacing: -0.2, color: adaptiveText4(context))),
          ),
          Text('${l.t('peak_label')} ${fmtCompact(peak, l)}',
              style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 118,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < buckets.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(child: _column(context, buckets[i], bounds, order)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Text(buckets.first.label, style: TextStyle(fontSize: 11, color: adaptiveText4(context))),
          const Spacer(),
          Text(buckets.last.label, style: TextStyle(fontSize: 11, color: adaptiveText4(context))),
        ]),
        const SizedBox(height: 8),
        // Логарифм — это не деталь реализации: без подписи читатель сравнивал бы
        // высоты столбиков напрямую и ошибался бы на порядок.
        Text('${l.t('log_scale_note')} ${fmtCompact(bounds.$1, l)} — ${fmtCompact(bounds.$2, l)}',
            style: TextStyle(fontSize: 11, height: 1.35, color: adaptiveText4(context))),
        const SizedBox(height: 10),
        Wrap(spacing: 12, runSpacing: 6, children: [
          for (final g in groups)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: kindColor(context, (g['group'] ?? 'other').toString()),
                    borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 6),
              Text((g['label'] ?? '').toString(),
                  style: TextStyle(fontSize: 12, color: adaptiveText3(context))),
            ]),
        ]),
      ]),
    );
  }

  /// Границы логарифмической шкалы — степени десяти вокруг данных.
  ///
  /// Дневной расход отличается в тысячи раз: десятки токенов в тихий день
  /// против сотен тысяч в день массовой проверки работ. На линейной шкале всё,
  /// кроме пика, ложится в пиксель — именно так график и выглядел раньше.
  (double bottom, double top) _logBounds(List<_Bucket> buckets) {
    final values = buckets.where((b) => b.total > 0).map((b) => b.total).toList();
    if (values.isEmpty) return (1, 10);
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final bottom = math.max(1.0, math.pow(10, (math.log(min) / math.ln10).floor()).toDouble());
    final top = math.max(bottom * 10, math.pow(10, (math.log(max) / math.ln10).ceil()).toDouble());
    return (bottom, top);
  }

  Widget _column(BuildContext context, _Bucket b, (double, double) bounds, List<String> order) {
    const maxH = 112.0;
    // День без запросов — тонкая полоска подложки: пустое место читалось бы
    // как «столбик не нарисовался».
    if (b.total <= 0) {
      return Container(
        height: 2,
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(1)),
      );
    }

    // Преобладающий вид расхода за день: на логарифмической шкале стек не имеет
    // смысла (доли сегментов перестают складываться в целое), поэтому столбик
    // одноцветный, а полная разбивка живёт в карточках выше.
    var group = 'other';
    var best = 0;
    for (final g in order) {
      final v = b.byGroup[g] ?? 0;
      if (v > best) {
        best = v;
        group = g;
      }
    }

    final span = (math.log(bounds.$2) - math.log(bounds.$1)) / math.ln10;
    final frac = span <= 0
        ? 1.0
        : ((math.log(b.total) / math.ln10) - (math.log(bounds.$1) / math.ln10)) / span;
    final height = (frac * maxH).clamp(4.0, maxH);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      child: SizedBox(
        height: height,
        child: ColoredBox(color: kindColor(context, group)),
      ),
    );
  }

  List<_Bucket> _buckets() {
    final raw = <_Bucket>[];
    for (final d in days) {
      final m = d as Map;
      final byGroup = <String, int>{};
      for (final e in ((m['kinds'] as Map?) ?? const {}).entries) {
        final g = endpointGroups[e.key.toString()] ?? 'other';
        byGroup[g] = (byGroup[g] ?? 0) + (e.value as num? ?? 0).toInt();
      }
      raw.add(_Bucket(
        date: (m['date'] ?? '').toString(),
        total: (m['total_tokens'] as num? ?? 0).toInt(),
        byGroup: byGroup,
      ));
    }
    if (raw.length <= 92) return raw;
    // Недельные корзины: сумма семи дней, подпись — по первому дню недели.
    final weeks = <_Bucket>[];
    for (var i = 0; i < raw.length; i += 7) {
      final chunk = raw.sublist(i, (i + 7).clamp(0, raw.length));
      final byGroup = <String, int>{};
      var total = 0;
      for (final b in chunk) {
        total += b.total;
        b.byGroup.forEach((k, v) => byGroup[k] = (byGroup[k] ?? 0) + v);
      }
      weeks.add(_Bucket(date: chunk.first.date, total: total, byGroup: byGroup));
    }
    return weeks;
  }
}

class _Bucket {
  _Bucket({required this.date, required this.total, required this.byGroup});

  final String date;
  final int total;
  final Map<String, int> byGroup;

  /// Подпись оси: «12.08» — год в графике за период не нужен.
  String get label {
    final parts = date.split('-');
    return parts.length == 3 ? '${parts[2]}.${parts[1]}' : date;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: adaptiveText3(context))),
      );
}
