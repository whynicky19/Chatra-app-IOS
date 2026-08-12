import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/classes_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';
import '../../utils/dates.dart';
import '../../utils/haptics.dart';
import '../../utils/nav_guard.dart';
import '../../widgets/inset_group.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/tappable.dart';

enum _NType { newAssignment, deadline, grade }

class _Notif {
  final String key;
  final _NType type;
  final String title;
  final String body;
  final DateTime date;
  final bool isRead;
  final int? classId;
  const _Notif({required this.key, required this.type, required this.title, required this.body, required this.date, this.isRead = false, this.classId});
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<_Notif> _notifs = [];
  late final ClassesProvider _classesProvider = context.read<ClassesProvider>();

  @override void initState() { super.initState(); _load(); }

  Map<String, Map<String, bool>> _states = {};

  bool _isRead(String key) => _states[key]?['read'] == true;
  bool _isDismissed(String key) => _states[key]?['dismissed'] == true;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final api = context.read<ApiService>();
    final uid = context.read<AuthProvider>().userId ?? 0;
    final l = context.read<L10n>();
    final prefs = await SharedPreferences.getInstance();

    final joinedIds = (prefs.getStringList('joined_classes_$uid') ?? []).map(int.parse).toSet();

    final now = DateTime.now();
    final notifs = <_Notif>[];

    List<dynamic> allAssignments = [];
    List<dynamic> mySubs = [];
    List<dynamic> posts = [];
    List<dynamic> states = [];

    await Future.wait([
      () async { try { allAssignments = await api.getAssignments(); } catch (_) {} }(),
      () async { try { mySubs = await api.getMySubmissions(); } catch (_) {} }(),
      () async { try { posts = await api.getPosts(); } catch (_) {} }(),
      () async { try { states = await api.getNotifStates(); } catch (_) {} }(),
    ]);

    // Не выходим по !mounted здесь: пользователь мог уже нажать «назад» —
    // но отметка прочитанным (ниже) и синхронизация бейджа всё равно должны
    // отработать, иначе счётчик на главном экране зависает на старом значении.
    _states = {
      for (final s in states)
        (s['notif_key'] ?? '').toString(): {
          'read': s['read'] == true,
          'dismissed': s['dismissed'] == true,
        }
    };

    final classNames = <int, String>{};
    final existingClassIds = <int>{};
    for (final p in posts) {
      try {
        final b = jsonDecode(p['body']);
        if (b['type'] == 'class') {
          final cid = (p['id'] as num).toInt();
          classNames[cid] = p['title']?.toString() ?? l.t('class_label');
          existingClassIds.add(cid);
        }
      } catch (_) {}
    }

    final activeJoinedIds = joinedIds.intersection(existingClassIds);

    allAssignments = allAssignments.where(
      (a) => existingClassIds.contains((a['class_id'] as num?)?.toInt()),
    ).toList();

    for (final sub in mySubs) {
      if (sub['status'] != 'graded' || sub['grade'] == null) continue;
      final subId = (sub['id'] as num?)?.toInt() ?? 0;
      final aId = (sub['assignment_id'] as num?)?.toInt();
      final assignment = aId != null ? allAssignments.firstWhere((a) => a['id'] == aId, orElse: () => null) : null;
      final cid = (assignment?['class_id'] as num?)?.toInt();
      if (cid != null && !existingClassIds.contains(cid)) continue;
      final nKey = 'grade:$subId';
      if (_isDismissed(nKey)) continue;
      final score = sub['grade']['score'];
      final aTitle = assignment?['title']?.toString() ?? l.t('assignment');
      notifs.add(_Notif(
        key: nKey,
        type: _NType.grade,
        title: l.t('notif_graded'),
        body: '"$aTitle" — $score ${l.t('pts')}',
        date: sub['submitted_at'] != null ? (parseServerDate(sub['submitted_at']) ?? now) : now,
        isRead: _isRead(nKey),
        classId: cid,
      ));
    }

    final filtered = activeJoinedIds.isEmpty
        ? <dynamic>[]
        : allAssignments.where((a) => activeJoinedIds.contains((a['class_id'] as num?)?.toInt())).toList();

    for (final a in filtered) {
      final aId = (a['id'] as num?)?.toInt() ?? 0;
      final aTitle = a['title']?.toString() ?? l.t('assignment');
      final cid = (a['class_id'] as num?)?.toInt();
      final cName = cid != null ? (classNames[cid] ?? '') : '';
      final createdAt = a['created_at'] != null ? parseServerDate(a['created_at']) : null;
      final deadline = a['deadline'] != null ? parseServerDate(a['deadline']) : null;
      final sub = mySubs.firstWhere((s) => s['assignment_id'] == aId, orElse: () => null);

      if (createdAt != null && now.difference(createdAt).inDays <= 7) {
        final nKey = 'assignment:$aId';
        if (!_isDismissed(nKey)) {
          notifs.add(_Notif(
            key: nKey,
            type: _NType.newAssignment,
            title: l.t('new_assignment'),
            body: '"$aTitle"${cName.isNotEmpty ? '  •  $cName' : ''}',
            date: createdAt,
            isRead: _isRead(nKey),
            classId: cid,
          ));
        }
      }

      if (deadline != null && deadline.isAfter(now) && deadline.difference(now).inHours <= 48 && sub == null) {
        final nKey = 'deadline:$aId';
        if (!_isDismissed(nKey)) {
          final diff = deadline.difference(now);
          final timeStr = diff.inHours >= 1 ? '${diff.inHours} ${l.t('hours_short')}' : '${diff.inMinutes} ${l.t('minutes_short')}';
          notifs.add(_Notif(
            key: nKey,
            type: _NType.deadline,
            title: l.t('notif_deadline'),
            body: '"$aTitle"  •  $timeStr',
            date: deadline,
            isRead: false,
            classId: cid,
          ));
        }
      }
    }

    if (activeJoinedIds.length < joinedIds.length) {
      await prefs.setStringList('joined_classes_$uid', activeJoinedIds.map((id) => '$id').toList());
    }

    notifs.sort((a, b) {
      if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
      return b.date.compareTo(a.date);
    });

    if (mounted) setState(() { _notifs = notifs; _loading = false; });

    final toMark = notifs
        .where((n) => n.type != _NType.deadline && !_isRead(n.key))
        .map((n) => n.key)
        .toList();
    if (toMark.isNotEmpty) {
      for (final k in toMark) {
        _states[k] = {'read': true, 'dismissed': _isDismissed(k)};
      }
      try { await api.markAllNotifsRead(toMark); } catch (_) {}
    }
    // Бейдж на главном экране синхронизируем сразу из локально посчитанного
    // состояния, а не повторным запросом к серверу после закрытия экрана —
    // тот запрос мог обогнать markAllNotifsRead и вернуть старое "непрочитано".
    _syncBadge(notifs);
  }

  void _syncBadge(List<_Notif> notifs) {
    _classesProvider.notifBadge.value =
        notifs.where((n) => n.type != _NType.deadline && !_isRead(n.key)).length;
  }

  void _markRead(String nKey) {
    if (_isRead(nKey)) return;
    setState(() {
      _states[nKey] = {'read': true, 'dismissed': _isDismissed(nKey)};
      _notifs = _notifs.map((n) => n.key == nKey
          ? _Notif(key: n.key, type: n.type, title: n.title, body: n.body,
              date: n.date, isRead: true, classId: n.classId)
          : n).toList();
    });
    _syncBadge(_notifs);
    try { context.read<ApiService>().setNotifState(nKey, read: true); } catch (_) {}
  }

  Future<void> _markAllRead() async {
    final toMark = _notifs.where((n) => !n.isRead).map((n) => n.key).toList();
    if (toMark.isEmpty) return;
    hapticLight();
    setState(() {
      for (final k in toMark) {
        _states[k] = {'read': true, 'dismissed': _isDismissed(k)};
      }
      _notifs = _notifs.map((n) => n.isRead
          ? n
          : _Notif(key: n.key, type: n.type, title: n.title, body: n.body,
              date: n.date, isRead: true, classId: n.classId)).toList();
    });
    _syncBadge(_notifs);
    try { await context.read<ApiService>().markAllNotifsRead(toMark); } catch (_) {}
  }

  Future<void> _dismiss(String nKey) async {
    setState(() {
      _notifs.removeWhere((n) => n.key == nKey);
      _states[nKey] = {'read': _isRead(nKey), 'dismissed': true};
    });
    _syncBadge(_notifs);
    try { await context.read<ApiService>().setNotifState(nKey, dismissed: true); } catch (_) {}
  }

  List<Object> _grouped(L10n l) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final weekStart = todayStart.subtract(const Duration(days: 7));
    int bucketOf(DateTime d) {
      if (!d.isBefore(todayStart)) return 0;
      if (!d.isBefore(yesterdayStart)) return 1;
      if (!d.isBefore(weekStart)) return 2;
      return 3;
    }
    final buckets = <int, List<_Notif>>{};
    for (final n in _notifs) {
      buckets.putIfAbsent(bucketOf(n.date), () => []).add(n);
    }
    const keys = ['notif_today', 'notif_yesterday', 'notif_this_week', 'notif_earlier'];
    final out = <Object>[];
    for (var b = 0; b < 4; b++) {
      final list = buckets[b];
      if (list == null || list.isEmpty) continue;
      out.add(l.t(keys[b]));
      out.addAll(list);
    }
    return out;
  }

  String _timeAgo(DateTime date, L10n l) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return l.t('just_now');
    if (diff.inHours < 1) return '${diff.inMinutes} ${l.t('min_ago')}';
    if (diff.inDays < 1) return '${diff.inHours} ${l.t('hr_ago')}';
    if (diff.inDays < 7) return '${diff.inDays} ${l.t('day_ago')}';
    final d = date;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final surface = Theme.of(context).colorScheme.surface;
    final unread = _notifs.where((n) => !n.isRead).length;
    final grouped = _grouped(l);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Панель навигации в духе iOS: слева — «назад» одним глифом (без
        // рамки-квадрата, которого в системных барах не бывает), справа —
        // текстовое действие акцентом, а не цветная пилюля.
        Padding(padding: const EdgeInsets.fromLTRB(8, 4, 16, 2), child: Row(children: [
          Tappable(onTap: () => Navigator.pop(context),
            label: 'Назад',
            child: SizedBox(width: 44, height: 44,
              child: Icon(CupertinoIcons.back, size: 26, color: Theme.of(context).colorScheme.primary))),
          const Spacer(),
          if (!_loading && unread > 0)
            Tappable(
              onTap: _markAllRead,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Text(l.t('mark_all_read'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.primary)),
              ),
            )
          else
            Tappable(onTap: _load,
              label: 'Обновить',
              child: SizedBox(width: 44, height: 44,
                child: Icon(CupertinoIcons.refresh, size: 20, color: Theme.of(context).colorScheme.primary))),
        ])),

        // Крупный заголовок отдельной строкой под баром — та же вертикальная
        // структура, что у нативного largeTitle.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('notifications'),
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: adaptiveText1(context))),
            if (!_loading) ...[
              const SizedBox(height: 4),
              Row(children: [
                if (unread > 0)
                  Container(width: 7, height: 7, margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle))
                else ...[
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 14, color: C.green.withValues(alpha: 0.85)),
                  const SizedBox(width: 5),
                ],
                Flexible(child: Text(unread > 0 ? '$unread ${l.t('notif_unread')}' : l.t('all_read'),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context), fontWeight: FontWeight.w500))),
              ]),
            ],
          ]),
        ),

        Expanded(child: _loading
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              itemCount: 5,
              itemBuilder: (ctx, i) => TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 260 + i * 70),
                curve: Curves.easeOut,
                builder: (_, t, child) => Opacity(opacity: t, child: child),
                child: const SkeletonNotifCard(),
              ),
            )
          : _notifs.isEmpty
            ? _emptyState()
            : CustomScrollView(
                slivers: [
                  CupertinoSliverRefreshControl(onRefresh: _load),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    sliver: SliverList(delegate: SliverChildBuilderDelegate(
                      childCount: grouped.length,
                      (ctx, i) {
                    final item = grouped[i];
                    if (item is String) {
                      return Padding(
                        padding: EdgeInsets.only(left: 6, top: i == 0 ? 2 : 18, bottom: 10),
                        child: Text(item.toUpperCase(), style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: adaptiveText3(context), letterSpacing: 0.6)),
                      );
                    }
                    final n = item as _Notif;
                    final cfg = _config(n.type);
                    final canNavigate = n.classId != null;
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(n.key),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 320 + i * 45),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child)),
                      child: RepaintBoundary(child: Dismissible(
                        key: ValueKey('dismiss_${n.key}'),
                        direction: DismissDirection.endToStart,
                        dismissThresholds: const {DismissDirection.endToStart: 0.4},
                        onDismissed: (_) {
                          hapticMedium();
                          _dismiss(n.key);
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: C.red,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 22),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.trash_fill, color: Colors.white, size: 22),
                            const SizedBox(height: 3),
                            Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                        child: _NotifCard(
                          notif: n,
                          config: cfg,
                          canNavigate: canNavigate,
                          surface: surface,
                          timeAgo: _timeAgo(n.date, l),
                          onTap: () {
                            _markRead(n.key);
                            if (canNavigate) {
                              guardedPush(context, MaterialPageRoute(
                                builder: (_) => ClassDetailScreen(classId: n.classId!, initialTab: 1)));
                            }
                          },
                        ),
                      )),
                    );
                      },
                    )),
                  ),
                ],
              )),
      ])),
    );
  }

  Map<String, dynamic> _config(_NType type) {
    switch (type) {
      case _NType.grade:
        return {'icon': CupertinoIcons.rosette, 'color': Theme.of(context).colorScheme.primary, 'bg': Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)};
      case _NType.deadline:
        return {'icon': CupertinoIcons.clock_fill, 'color': C.red, 'bg': C.red.withValues(alpha: 0.10)};
      case _NType.newAssignment:
        return {'icon': CupertinoIcons.doc_text_fill, 'color': C.indigo, 'bg': C.indigo.withValues(alpha: 0.08)};
    }
  }

  Widget _emptyState() {
    final l = context.read<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    return Center(child: Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 60),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76,
          decoration: BoxDecoration(
            gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.03)]),
            shape: BoxShape.circle),
          child: Icon(CupertinoIcons.bell_fill, size: 32, color: primary)),
        const SizedBox(height: 18),
        Text(l.t('no_notif'), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Text(l.t('no_notif_sub'), textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context), height: 1.4)),
      ]),
    ));
  }
}

/// Карточка одного уведомления в духе списка Apple Mail: плоский цветной
/// значок, время — в строке заголовка, непрочитанное отмечено точкой у
/// заголовка и более насыщенной подложкой значка.
///
/// Раньше непрочитанное дополнительно обводилось цветной рамкой в 1.2px по
/// всей карточке: в списке из нескольких непрочитанных экран превращался в
/// набор конкурирующих цветных прямоугольников. Теперь рамка всегда одна и та
/// же волосяная, а «непрочитанность» несут точка, вес заголовка и значок —
/// ровно как в Mail.
class _NotifCard extends StatefulWidget {
  final _Notif notif;
  final Map<String, dynamic> config;
  final bool canNavigate;
  final Color surface;
  final String timeAgo;
  final VoidCallback onTap;

  const _NotifCard({
    required this.notif,
    required this.config,
    required this.canNavigate,
    required this.surface,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  State<_NotifCard> createState() => _NotifCardState();
}

class _NotifCardState extends State<_NotifCard> {
  @override
  Widget build(BuildContext context) {
    final n = widget.notif;
    final c = widget.config['color'] as Color;
    final icon = widget.config['icon'] as IconData;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GroupRow.card(
        onTap: widget.onTap,
        color: widget.surface,
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: n.isRead ? 0.10 : 0.18),
              borderRadius: BorderRadius.circular(AppRadii.chip),
            ),
            child: Icon(icon, size: 19, color: c)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!n.isRead) ...[
                Padding(padding: const EdgeInsets.only(top: 6),
                  child: Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                const SizedBox(width: 7),
              ],
              Expanded(child: Text(n.title, style: TextStyle(
                fontSize: 16, fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w600,
                letterSpacing: -0.3, color: adaptiveText1(context), height: 1.25))),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(widget.timeAgo, style: TextStyle(
                  fontSize: 13, color: adaptiveText4(context), fontWeight: FontWeight.w400)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: adaptiveText3(context), height: 1.35)),
          ])),
          if (widget.canNavigate) ...[
            const SizedBox(width: 6),
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Icon(CupertinoIcons.chevron_right, size: 14, color: adaptiveText4(context).withValues(alpha: 0.7))),
          ],
        ]),
      ),
    );
  }
}
