import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../classes/class_detail_screen.dart';

enum _NType { newAssignment, deadline, grade }

class _Notif {
  final _NType type;
  final String title;
  final String body;
  final DateTime date;
  final bool isRead;
  final int? classId;
  const _Notif({required this.type, required this.title, required this.body, required this.date, this.isRead = false, this.classId});
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  List<_Notif> _notifs = [];

  @override void initState() { super.initState(); _load(); }

  static const _readTtlDays = 2;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final api = context.read<ApiService>();
    final uid = context.read<AuthProvider>().userId ?? 0;
    final prefs = await SharedPreferences.getInstance();

    final joinedIds = (prefs.getStringList('joined_classes_$uid') ?? []).map(int.parse).toSet();
    final seenAsgn = (prefs.getStringList('notif_seen_asgn_$uid') ?? []).map(int.parse).toSet();
    final seenGrade = (prefs.getStringList('notif_seen_grade_$uid') ?? []).map(int.parse).toSet();

    // read-at timestamps: id -> ISO string
    Map<int, DateTime> readAtAsgn = {};
    Map<int, DateTime> readAtGrade = {};
    try {
      final rawA = prefs.getString('notif_read_at_asgn_$uid');
      if (rawA != null) {
        (jsonDecode(rawA) as Map).forEach((k, v) {
          final dt = DateTime.tryParse(v.toString());
          if (dt != null) readAtAsgn[int.parse(k.toString())] = dt;
        });
      }
      final rawG = prefs.getString('notif_read_at_grade_$uid');
      if (rawG != null) {
        (jsonDecode(rawG) as Map).forEach((k, v) {
          final dt = DateTime.tryParse(v.toString());
          if (dt != null) readAtGrade[int.parse(k.toString())] = dt;
        });
      }
    } catch (_) {}

    final now = DateTime.now();
    final notifs = <_Notif>[];
    final newSeenAsgn = Set<int>.from(seenAsgn);
    final newSeenGrade = Set<int>.from(seenGrade);

    List<dynamic> allAssignments = [];
    List<dynamic> mySubs = [];
    List<dynamic> posts = [];

    await Future.wait([
      () async { try { allAssignments = await api.getAssignments(); } catch (_) {} }(),
      () async { try { mySubs = await api.getMySubmissions(); } catch (_) {} }(),
      () async { try { posts = await api.getPosts(); } catch (_) {} }(),
    ]);

    // Build class name map from posts and collect existing class IDs
    final classNames = <int, String>{};
    final existingClassIds = <int>{};
    for (final p in posts) {
      try {
        final b = jsonDecode(p['body']);
        if (b['type'] == 'class') {
          final cid = (p['id'] as num).toInt();
          classNames[cid] = p['title']?.toString() ?? 'Класс';
          existingClassIds.add(cid);
        }
      } catch (_) {}
    }

    // Remove deleted classes from joined set so we don't show stale notifications
    final activeJoinedIds = joinedIds.intersection(existingClassIds);

    final l = context.read<L10n>();

    // ── Grade notifications ──
    for (final sub in mySubs) {
      if (sub['status'] != 'graded' || sub['grade'] == null) continue;
      final subId = (sub['id'] as num?)?.toInt() ?? 0;
      final isRead = seenGrade.contains(subId);
      // Record read-at on first sight
      if (isRead && !readAtGrade.containsKey(subId)) readAtGrade[subId] = now;
      // Skip if read more than TTL days ago
      if (isRead) {
        final readAt = readAtGrade[subId];
        if (readAt != null && now.difference(readAt).inDays >= _readTtlDays) { newSeenGrade.add(subId); continue; }
      }
      final score = sub['grade']['score'];
      final aId = (sub['assignment_id'] as num?)?.toInt();
      final assignment = aId != null ? allAssignments.firstWhere((a) => a['id'] == aId, orElse: () => null) : null;
      final aTitle = assignment?['title']?.toString() ?? l.t('assignment');
      final cid = (assignment?['class_id'] as num?)?.toInt();
      notifs.add(_Notif(
        type: _NType.grade,
        title: l.t('notif_graded'),
        body: '"$aTitle" — $score ${l.t('pts')}',
        date: sub['submitted_at'] != null ? (DateTime.tryParse(sub['submitted_at']) ?? now) : now,
        isRead: isRead,
        classId: cid,
      ));
      newSeenGrade.add(subId);
    }

    // ── Assignment notifications (only for joined AND existing classes) ──
    final filtered = activeJoinedIds.isEmpty
        ? <dynamic>[]
        : allAssignments.where((a) => activeJoinedIds.contains((a['class_id'] as num?)?.toInt())).toList();

    for (final a in filtered) {
      final aId = (a['id'] as num?)?.toInt() ?? 0;
      final aTitle = a['title']?.toString() ?? l.t('assignment');
      final cid = (a['class_id'] as num?)?.toInt();
      final cName = cid != null ? (classNames[cid] ?? '') : '';
      final createdAt = a['created_at'] != null ? DateTime.tryParse(a['created_at']) : null;
      final deadline = a['deadline'] != null ? DateTime.tryParse(a['deadline']) : null;
      final sub = mySubs.firstWhere((s) => s['assignment_id'] == aId, orElse: () => null);

      // New assignment (last 7 days)
      if (createdAt != null && now.difference(createdAt).inDays <= 7) {
        final isRead = seenAsgn.contains(aId);
        if (isRead && !readAtAsgn.containsKey(aId)) readAtAsgn[aId] = now;
        final skip = isRead && (readAtAsgn[aId] != null && now.difference(readAtAsgn[aId]!).inDays >= _readTtlDays);
        if (!skip) {
          notifs.add(_Notif(
            type: _NType.newAssignment,
            title: l.t('new_assignment'),
            body: '"$aTitle"${cName.isNotEmpty ? '  •  $cName' : ''}',
            date: createdAt,
            isRead: isRead,
            classId: cid,
          ));
        }
        newSeenAsgn.add(aId);
      }

      // Deadline reminder (within 48 h, not submitted)
      if (deadline != null && deadline.isAfter(now) && deadline.difference(now).inHours <= 48 && sub == null) {
        final diff = deadline.difference(now);
        final timeStr = diff.inHours >= 1 ? '${diff.inHours} ${l.t('hours_short')}' : '${diff.inMinutes} ${l.t('minutes_short')}';
        notifs.add(_Notif(
          type: _NType.deadline,
          title: l.t('notif_deadline'),
          body: '"$aTitle"  •  $timeStr',
          date: deadline,
          isRead: false,
          classId: cid,
        ));
      }
    }

    // Persist cleaned joined list (remove deleted classes)
    if (activeJoinedIds.length < joinedIds.length) {
      await prefs.setStringList('joined_classes_$uid', activeJoinedIds.map((id) => '$id').toList());
    }

    // Persist seen state + read-at timestamps
    await Future.wait([
      prefs.setStringList('notif_seen_asgn_$uid', newSeenAsgn.map((id) => '$id').toList()),
      prefs.setStringList('notif_seen_grade_$uid', newSeenGrade.map((id) => '$id').toList()),
      prefs.setString('notif_read_at_asgn_$uid', jsonEncode(readAtAsgn.map((k, v) => MapEntry('$k', v.toIso8601String())))),
      prefs.setString('notif_read_at_grade_$uid', jsonEncode(readAtGrade.map((k, v) => MapEntry('$k', v.toIso8601String())))),
    ]);

    // Sort: unread first, then by date desc
    notifs.sort((a, b) {
      if (a.isRead != b.isRead) return a.isRead ? 1 : -1;
      return b.date.compareTo(a.date);
    });

    if (mounted) setState(() { _notifs = notifs; _loading = false; });
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 16), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40, decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.arrow_back, size: 20, color: adaptiveText1(context)))),
          SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.t('notifications'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: C.teal)),
            if (!_loading)
              Text(unread > 0 ? '$unread ${l.t('notif_unread')}' : l.t('all_read'), style: TextStyle(fontSize: 12, color: C.text4)),
          ])),
          GestureDetector(onTap: _load,
            child: Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.refresh, size: 18, color: C.text4))),
        ])),

        // Content
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: C.teal, strokeWidth: 2.5))
          : _notifs.isEmpty
            ? _emptyState()
            : RefreshIndicator(
                color: C.teal,
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: _notifs.length,
                  itemBuilder: (ctx, i) {
                    final n = _notifs[i];
                    final cfg = _config(n.type);
                    final canNavigate = n.classId != null;
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(i),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 320 + i * 45),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: child)),
                      child: GestureDetector(
                        onTap: canNavigate ? () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => ClassDetailScreen(classId: n.classId!, initialTab: 2))) : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: n.isRead ? surface : cfg['bg'] as Color,
                            borderRadius: BorderRadius.circular(18),
                            border: n.isRead ? null : Border.all(color: (cfg['color'] as Color).withOpacity(0.22)),
                            boxShadow: cardShadow(isDark),
                          ),
                          child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: (cfg['color'] as Color).withOpacity(n.isRead ? 0.08 : 0.14),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(cfg['icon'] as IconData, size: 20, color: cfg['color'] as Color)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(n.title, style: TextStyle(
                                  fontSize: 14, fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w800,
                                  color: adaptiveText1(context)))),
                                if (!n.isRead) Container(width: 8, height: 8, decoration: BoxDecoration(color: cfg['color'] as Color, shape: BoxShape.circle)),
                                if (canNavigate) Padding(padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.arrow_forward_ios_rounded, size: 11, color: C.text4)),
                              ]),
                              const SizedBox(height: 4),
                              Text(n.body, style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4)),
                              const SizedBox(height: 6),
                              Text(_timeAgo(n.date, l), style: TextStyle(
                                fontSize: 11, color: C.text4.withOpacity(0.7), fontWeight: FontWeight.w600)),
                            ])),
                          ])),
                        ),
                      ),
                    );
                  },
                ),
              )),
      ])),
    );
  }

  Map<String, dynamic> _config(_NType type) {
    switch (type) {
      case _NType.grade:
        return {'icon': Icons.star_rounded, 'color': C.teal, 'bg': C.teal.withOpacity(0.08)};
      case _NType.deadline:
        return {'icon': Icons.timer_rounded, 'color': Color(0xFFEF4444), 'bg': Color(0xFFEF4444).withOpacity(0.10)};
      case _NType.newAssignment:
        return {'icon': Icons.assignment_rounded, 'color': Color(0xFF6366F1), 'bg': Color(0xFF6366F1).withOpacity(0.08)};
    }
  }

  Widget _emptyState() {
    final l = context.read<L10n>();
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 80, height: 80, decoration: BoxDecoration(color: C.teal.withOpacity(0.08), shape: BoxShape.circle),
        child: Icon(Icons.notifications_none_rounded, size: 38, color: C.teal)),
      SizedBox(height: 20),
      Text(l.t('no_notif'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
      SizedBox(height: 6),
      Text(l.t('no_notif_sub'), style: TextStyle(fontSize: 14, color: C.text4, height: 1.5), textAlign: TextAlign.center),
    ]));
  }
}
