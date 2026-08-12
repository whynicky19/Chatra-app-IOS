import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unread = _notifs.where((n) => !n.isRead).length;
    final grouped = _grouped(l);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16), child: Row(children: [
          Tappable(onTap: () => Navigator.pop(context),
            label: 'Назад',
            child: Container(width: 40, height: 40, alignment: Alignment.center,
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile),
                border: Border.all(color: adaptiveBorder(context))),
              child: Icon(CupertinoIcons.chevron_left, size: 20, color: adaptiveText1(context)))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('notifications'), style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: adaptiveText1(context))),
            if (!_loading) ...[
              const SizedBox(height: 3),
              Row(children: [
                if (unread > 0) ...[
                  Container(width: 6, height: 6, margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle)),
                ] else
                  Icon(CupertinoIcons.checkmark_circle_fill, size: 13, color: C.green.withValues(alpha: 0.8)),
                if (unread == 0) const SizedBox(width: 5),
                Flexible(child: Text(unread > 0 ? '$unread ${l.t('notif_unread')}' : l.t('all_read'),
                  overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: adaptiveText3(context), fontWeight: FontWeight.w500))),
              ]),
            ],
          ])),
          const SizedBox(width: 8),
          if (!_loading && unread > 0)
            Tappable(
              onTap: _markAllRead,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(CupertinoIcons.checkmark_alt, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 5),
                  Text(l.t('mark_all_read'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                ]),
              ),
            )
          else
            Tappable(onTap: _load,
              label: 'Обновить',
              child: Container(width: 40, height: 40, alignment: Alignment.center,
                decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile),
                  border: Border.all(color: adaptiveBorder(context))),
                child: const Icon(CupertinoIcons.refresh, size: 18, color: C.text4))),
        ])),

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
                        padding: EdgeInsets.only(left: 6, top: i == 0 ? 2 : 14, bottom: 8),
                        child: Text(item.toUpperCase(), style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: adaptiveText3(context), letterSpacing: 1.0)),
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
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: C.red,
                            borderRadius: BorderRadius.circular(AppRadii.card),
                          ),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(CupertinoIcons.trash, color: Colors.white, size: 24),
                            const SizedBox(height: 4),
                            Text(l.t('delete'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                        child: _NotifCard(
                          notif: n,
                          config: cfg,
                          canNavigate: canNavigate,
                          isDark: isDark,
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
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: Icon(CupertinoIcons.bell_fill, size: 38, color: Theme.of(context).colorScheme.primary)),
      const SizedBox(height: 20),
      Text(l.t('no_notif'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
      const SizedBox(height: 6),
      Text(l.t('no_notif_sub'), style: TextStyle(fontSize: 15, color: adaptiveText3(context), height: 1.5), textAlign: TextAlign.center),
    ]));
  }
}

/// Карточка одного уведомления в духе списка Apple Mail: плоский цветной
/// значок-иконка (без градиента), время — в строке заголовка, а не отдельной
/// строкой снизу, непрочитанное отмечено точкой у заголовка и мягкой цветной
/// рамкой карточки — вместо цветной заливки всей плашки. Лёгкое сжатие при
/// нажатии — как у FileCard.
class _NotifCard extends StatefulWidget {
  final _Notif notif;
  final Map<String, dynamic> config;
  final bool canNavigate;
  final bool isDark;
  final Color surface;
  final String timeAgo;
  final VoidCallback onTap;

  const _NotifCard({
    required this.notif,
    required this.config,
    required this.canNavigate,
    required this.isDark,
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

    return Tappable(
      behavior: HitTestBehavior.opaque,
      scale: 0.98,
      onTap: widget.onTap,
      child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.surface,
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: cardShadow(widget.isDark),
            border: Border.all(
              color: n.isRead ? adaptiveBorder(context).withValues(alpha: 0.5) : c.withValues(alpha: 0.35),
              width: n.isRead ? 1 : 1.2,
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 44, height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.withValues(alpha: n.isRead ? 0.09 : 0.16),
                borderRadius: BorderRadius.circular(AppRadii.tile),
              ),
              child: Icon(icon, size: 20, color: c)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!n.isRead) ...[
                  Padding(padding: const EdgeInsets.only(top: 5),
                    child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle))),
                  const SizedBox(width: 6),
                ],
                Expanded(child: Text(n.title, style: TextStyle(
                  fontSize: 15, fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                  color: adaptiveText1(context), height: 1.25))),
                const SizedBox(width: 8),
                Text(widget.timeAgo, style: TextStyle(
                  fontSize: 11.5, color: adaptiveText3(context), fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 4),
              Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: adaptiveText3(context), height: 1.4)),
            ])),
            if (widget.canNavigate) ...[
              const SizedBox(width: 4),
              Padding(padding: const EdgeInsets.only(top: 2),
                child: Icon(CupertinoIcons.chevron_right, size: 13, color: C.text4.withValues(alpha: 0.5))),
            ],
          ]),
        ),
    );
  }
}
