import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/toast.dart';

class ClassAssignmentsTab extends StatefulWidget {
  final List<dynamic> assignments;
  final List<dynamic> mySubs;
  final Map<String, dynamic> rating;
  final bool isTeacher;
  final int classId;
  final bool isLoading;
  final VoidCallback onRefresh;
  final void Function(dynamic a) onEditAssignment;
  final void Function(String url, String name) onOpenFile;

  const ClassAssignmentsTab({
    super.key,
    required this.assignments,
    required this.mySubs,
    required this.rating,
    required this.isTeacher,
    required this.classId,
    required this.isLoading,
    required this.onRefresh,
    required this.onEditAssignment,
    required this.onOpenFile,
  });

  @override
  State<ClassAssignmentsTab> createState() => _ClassAssignmentsTabState();
}

class _ClassAssignmentsTabState extends State<ClassAssignmentsTab> {
  final Set<int> _expandedCriteria = {};

  dynamic _subFor(int aId) => widget.mySubs.firstWhere((s) => s['assignment_id'] == aId, orElse: () => null);

  String _fmtDate(String? d) {
    if (d == null) return '';
    try { final dt = DateTime.parse(d); return '${dt.day}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; } catch (_) { return d; }
  }

  String _fileDisplayName(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
    } catch (_) { return url; }
  }

  String _cleanContent(String content) {
    return content
        .replaceAll(RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  List<String> _extractFilesFromText(String text) {
    final matches = RegExp(r'https?://[^\s"<>]+\.(pdf|doc|docx|txt|png|jpg|jpeg|pptx?|xlsx?)', caseSensitive: false).allMatches(text);
    return matches.map((m) => context.read<ApiService>().fixUrl(m.group(0)!)).toList();
  }

  List<String> _parseFileUrls(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((f) => context.read<ApiService>().fixUrl(f.toString())).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((f) => context.read<ApiService>().fixUrl(f.toString())).where((s) => s.isNotEmpty).toList();
        }
        if (decoded is String && decoded.isNotEmpty) return [context.read<ApiService>().fixUrl(decoded)];
      } catch (_) {}
      if (raw.startsWith('http') || raw.startsWith('/')) return [context.read<ApiService>().fixUrl(raw)];
    }
    return [];
  }

  List<String> _extractAssignmentFiles(dynamic listA, [dynamic detailA]) {
    final result = <String>{};
    for (final src in [listA, if (detailA != null) detailA]) {
      if (src == null) continue;
      result.addAll(_parseFileUrls(src['file_urls']));
      result.addAll(_parseFileUrls(src['files']));
      result.addAll(_parseFileUrls(src['attachments']));
      if (src['file_url'] != null) result.add(context.read<ApiService>().fixUrl(src['file_url'].toString()));
      if (src['description'] != null) {
        result.addAll(_extractFilesFromText(src['description'].toString()));
      }
    }
    return result.where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> _fileTypeConfig(String ext) {
    switch (ext) {
      case 'pdf':
        return {'icon': CupertinoIcons.doc_text, 'color': const Color(0xFFE53E3E), 'bg': const Color(0xFFFFF5F5)};
      case 'pptx': case 'ppt':
        return {'icon': CupertinoIcons.film,       'color': const Color(0xFFDD6B20), 'bg': const Color(0xFFFFFAF0)};
      case 'doc': case 'docx':
        return {'icon': CupertinoIcons.doc_text,    'color': const Color(0xFF2B6CB0), 'bg': const Color(0xFFEBF8FF)};
      case 'xlsx': case 'xls':
        return {'icon': CupertinoIcons.square_grid_2x2,    'color': const Color(0xFF276749), 'bg': const Color(0xFFF0FFF4)};
      case 'txt': case 'md':
        return {'icon': CupertinoIcons.doc_plaintext,   'color': const Color(0xFF553C9A), 'bg': const Color(0xFFFAF5FF)};
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return {'icon': CupertinoIcons.photo,          'color': const Color(0xFF0C4A6E), 'bg': const Color(0xFFE0F2FE)};
      case 'mp4': case 'mov': case 'avi':
        return {'icon': CupertinoIcons.play_circle,    'color': const Color(0xFF6B21A8), 'bg': const Color(0xFFF5F3FF)};
      default:
        return {'icon': CupertinoIcons.doc, 'color': C.text4,             'bg': C.surface2};
    }
  }

  Widget _statBox(String val, String label, Color color) => Expanded(child: Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2))),
    child: Column(children: [Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)), SizedBox(height: 2), Text(label, style: TextStyle(fontSize: 11, color: C.text4))])));

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    if (widget.isLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2.5));
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avg = (widget.rating['avg_score'] ?? 0).round();
    final pct = (widget.rating['avg_percent'] ?? 0).round();

    return ListView(padding: EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
      if (!widget.isTeacher && widget.rating.isNotEmpty) Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF006475), Theme.of(context).colorScheme.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('your_rating'), style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              SizedBox(height: 8),
              RichText(text: TextSpan(children: [
                TextSpan(text: '$avg', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, height: 1)),
                TextSpan(text: ' /100', style: TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.w600)),
              ])),
              SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: avg / 100, backgroundColor: Colors.white24, color: Colors.white, minHeight: 4)),
              SizedBox(height: 4),
              Text('${l.t('performance')}: $pct%', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          )),
          SizedBox(width: 10),
          Expanded(child: Builder(builder: (_) {
            final now = DateTime.now();
            final upcoming = widget.assignments.where((a) {
              if (a['deadline'] == null) return false;
              final dl = DateTime.tryParse(a['deadline']);
              if (dl == null) return false;
              final sub = _subFor(a['id']);
              return dl.isAfter(now) && (sub == null || sub['status'] != 'graded');
            }).toList();
            upcoming.sort((a, b) => (a['deadline'] ?? '').compareTo(b['deadline'] ?? ''));
            if (upcoming.isEmpty) return Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('СЛЕД. ДЕДЛАЙН', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 16),
                Center(child: Icon(CupertinoIcons.checkmark_circle, size: 32, color: C.green)),
                SizedBox(height: 8),
                Center(child: Text('Всё сдано!', style: TextStyle(fontSize: 13, color: C.green, fontWeight: FontWeight.w600))),
              ]));
            final next = upcoming.first;
            final dl = DateTime.parse(next['deadline']);
            final diff = dl.difference(now);
            final days = diff.inDays;
            final hours = diff.inHours % 24;
            final months = ['ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НОЯ','ДЕК'];
            final remaining = days > 0 ? '$days дн. $hours ч.' : '$hours ч. ${diff.inMinutes % 60} мин.';
            return Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('СЛЕД. ДЕДЛАЙН', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 48, height: 56,
                    decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(months[dl.month - 1], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
                      Text('${dl.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, height: 1.1)),
                    ]),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(next['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    SizedBox(height: 2),
                    Text('Осталось: $remaining', style: TextStyle(fontSize: 11, color: days <= 1 ? C.red : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
                  ])),
                ]),
              ]),
            );
          })),
        ])),
      ),
      Row(children: [
        Text('Задания', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Spacer(),
        Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [Icon(CupertinoIcons.arrow_up_arrow_down, size: 14, color: C.text4), SizedBox(width: 4), Text(l.t('sort_deadline'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text4))])),
      ]),
      SizedBox(height: 12),
      if (widget.assignments.isEmpty) Container(padding: EdgeInsets.symmetric(vertical: 52), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.doc_text, size: 36, color: Theme.of(context).colorScheme.primary)),
        SizedBox(height: 18),
        Text(l.t('no_assignments'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
        SizedBox(height: 6),
        Text(widget.isTeacher ? 'Создайте первое задание' : 'Заданий пока нет',
          style: TextStyle(fontSize: 13, color: C.text4)),
      ]))),
      // Pre-compute lookup map once — avoids O(N×M) linear scans per card
      ...() {
        final subMap = <int, dynamic>{};
        for (final s in widget.mySubs) {
          subMap[(s['assignment_id'] as num).toInt()] = s;
        }
        return widget.assignments.asMap().entries.map((entry) {
        final i = entry.key; final a = entry.value;
        final sub = subMap[(a['id'] as num).toInt()];
        final status = sub?['status'];
        final grade = sub?['grade'];
        final isGraded = status == 'graded';
        final isSubmitted = status == 'submitted';
        final deadline = a['deadline'];
        final isLate = deadline != null && DateTime.tryParse(deadline)?.isBefore(DateTime.now()) == true && sub == null;

        Color statusColor = isGraded ? C.green : isSubmitted ? Theme.of(context).colorScheme.primary : isLate ? C.red : C.text4;
        Color statusBg = isGraded ? C.greenLt : isSubmitted ? adaptivePrimaryLt(context) : isLate ? C.redLt : adaptiveSurface2(context);
        String statusText = isGraded ? l.t('graded') : isSubmitted ? l.t('submitted') : isLate ? l.t('overdue') : l.t('new_status');
        IconData statusIcon = isGraded ? CupertinoIcons.checkmark_circle_fill : isSubmitted ? CupertinoIcons.arrow_up_doc : isLate ? CupertinoIcons.clock : CupertinoIcons.pencil;

        return TweenAnimationBuilder<double>(
          key: ValueKey('asgn_${a['id']}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 220 + i.clamp(0, 5) * 50),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
          child: RepaintBoundary(child: GestureDetector(
            onTap: () => _showAssignment(a, sub),
            child: Container(
              margin: EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: cardShadow(isDark),
              ),
              child: Column(children: [
                Padding(padding: EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                    child: Icon(statusIcon, color: statusColor, size: 22)),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(a['title'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 8),
                      Container(padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                        child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: statusColor))),
                    ]),
                    if (a['description'] != null && a['description'].toString().isNotEmpty)
                      Padding(padding: EdgeInsets.only(top: 4),
                        child: Text(a['description'], style: TextStyle(fontSize: 13, color: C.text4), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    SizedBox(height: 10),
                    Wrap(spacing: 12, children: [
                      if (deadline != null) Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.calendar, size: 12, color: isLate ? C.red : C.text4), SizedBox(width: 4),
                        Text(_fmtDate(deadline), style: TextStyle(fontSize: 12, color: isLate ? C.red : C.text4, fontWeight: FontWeight.w500)),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.star_fill, size: 14, color: Theme.of(context).colorScheme.primary), SizedBox(width: 3),
                        Text('${a['max_score'] ?? 100} ${l.t('pts')}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      ]),
                      if (grade != null) Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.checkmark_circle_fill, size: 12, color: C.green), SizedBox(width: 3),
                        Text('${grade['score']}/${a['max_score']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: C.green)),
                      ]),
                    ]),
                  ])),
                ])),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: adaptiveSurface2(context).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        SizedBox(width: 4),
                        Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                      ]),
                    ),
                    Spacer(),
                    Row(children: [
                      Text('Открыть', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      SizedBox(width: 3),
                      Icon(CupertinoIcons.chevron_right, size: 13, color: Theme.of(context).colorScheme.primary),
                    ]),
                  ]),
                ),
              ]),
            ),
          )),
        );
        }).toList();
      }(),
    ]);
  }

  void _showAssignment(dynamic a, dynamic sub) {
    final tc = TextEditingController(); bool busy = false; bool descHidden = false;
    final isTeacherOrAdmin = widget.isTeacher;
    List<dynamic> criteria = []; try { criteria = jsonDecode(a['criteria'] ?? '[]'); } catch (_) {}
    List<PlatformFile> pickedFiles = [];

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deadline = a['deadline'];
    final isLate = deadline != null && DateTime.tryParse(deadline)?.isBefore(DateTime.now()) == true && sub == null;
    final sheetStatusColor = sub?['status'] == 'graded' ? C.green
        : sub?['status'] == 'submitted' ? Theme.of(context).colorScheme.primary
        : isLate ? C.red : C.text4;
    final sheetStatusText = sub?['status'] == 'graded' ? 'Проверено'
        : sub?['status'] == 'submitted' ? 'Сдано'
        : isLate ? 'Просрочено' : 'Новое';

    final assignmentFuture = context.read<ApiService>().getAssignment((a['id'] as num).toInt());

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return DraggableScrollableSheet(
        expand: false, initialChildSize: 0.88, maxChildSize: 0.97, minChildSize: 0.5,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Container(
              decoration: BoxDecoration(
                color: isDark ? C.darkSurface : Colors.white,
                border: Border(bottom: BorderSide(color: adaptiveBorder(context), width: 1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 16, 0),
                  child: Row(children: [
                    Expanded(child: Center(child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)),
                    ))),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(width: 32, height: 32,
                        decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                        child: Icon(CupertinoIcons.xmark, color: C.text4, size: 16)),
                    ),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(7)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.doc_text, size: 11, color: Theme.of(context).colorScheme.primary),
                        SizedBox(width: 4),
                        Text('ЗАДАНИЕ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.6)),
                      ]),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(color: sheetStatusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(7)),
                      child: Text(sheetStatusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sheetStatusColor)),
                    ),
                  ]),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(a['title'] ?? '',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.2, letterSpacing: -0.3, color: adaptiveText1(context)),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 10, 20, 16),
                  child: Row(children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.star_fill, size: 13, color: Theme.of(context).colorScheme.primary), SizedBox(width: 4),
                        Text('${a['max_score'] ?? 100} баллов', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (deadline != null) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isLate ? C.red.withValues(alpha: 0.08) : adaptiveSurface2(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(CupertinoIcons.calendar, size: 12, color: isLate ? C.red : C.text4),
                          SizedBox(width: 4),
                          Text(_fmtDate(deadline), style: TextStyle(fontSize: 12, color: isLate ? C.red : C.text4, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
            Expanded(child: ListView(controller: sc, padding: EdgeInsets.fromLTRB(20, 20, 20, 24), children: [
        FutureBuilder<Map<String, dynamic>>(
          future: assignmentFuture,
          builder: (ctx, snap) {
            final detailA   = snap.data;
            final isLoading = snap.connectionState == ConnectionState.waiting;
            final hasError  = snap.hasError;

            final descText = _cleanContent(
              ((detailA?['description'] ?? a['description'])?.toString()) ?? '');

            final allFiles = _extractAssignmentFiles(a, detailA);

            final rawFromList   = a['file_urls'];
            final rawFromDetail = detailA?['file_urls'];
            final showDebug = !isLoading && allFiles.isEmpty &&
                (rawFromList != null || rawFromDetail != null || hasError);

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (descText.isNotEmpty) ...[
                Row(children: [
                  Container(width: 3, height: 16, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2))),
                  SizedBox(width: 8),
                  Text('Описание', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                  Spacer(),
                  GestureDetector(
                    onTap: () => setS(() => descHidden = !descHidden),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedRotation(
                          turns: descHidden ? 0.5 : 0.0,
                          duration: Duration(milliseconds: 220),
                          child: Icon(CupertinoIcons.chevron_up, size: 14, color: C.text4),
                        ),
                        SizedBox(width: 4),
                        Text(descHidden ? 'Показать' : 'Скрыть', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: C.text4)),
                      ]),
                    ),
                  ),
                ]),
                AnimatedSize(
                  duration: Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: descHidden
                      ? SizedBox.shrink()
                      : Padding(
                          padding: EdgeInsets.only(top: 10, bottom: 20),
                          child: Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(color: isDark ? C.darkSurface2 : C.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10))),
                            child: Text(descText, style: TextStyle(fontSize: 14, height: 1.65)),
                          ),
                        ),
                ),
              ],
              if (isLoading) Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                  SizedBox(width: 10),
                  Text('Загрузка файлов...', style: TextStyle(fontSize: 13, color: C.text4)),
                ]),
              )
              else if (allFiles.isNotEmpty) ...[
                Row(children: [
                  Container(width: 3, height: 16, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(2))),
                  SizedBox(width: 8),
                  Text('Прикреплённые файлы', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.3)),
                ]),
                SizedBox(height: 10),
                ...allFiles.asMap().entries.map((entry) {
              final f = entry.value;
              final name = _fileDisplayName(f);
              final ext = name.split('.').last.toLowerCase();
              final fc = _fileTypeConfig(ext);
              final fileIcon = fc['icon'] as IconData;
              final fileColor = fc['color'] as Color;
              final fileBg = fc['bg'] as Color;
              return GestureDetector(
                onTap: () => widget.onOpenFile(f, name),
                child: Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? C.darkSurface2 : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: fileColor.withValues(alpha: 0.2)),
                    boxShadow: [BoxShadow(color: fileColor.withValues(alpha: 0.06), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Row(children: [
                    Container(width: 42, height: 42, decoration: BoxDecoration(color: fileBg, borderRadius: BorderRadius.circular(11)),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(fileIcon, size: 18, color: fileColor),
                        SizedBox(height: 1),
                        Text(ext.toUpperCase(), style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: fileColor)),
                      ])),
                    SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                      Text('Нажмите для открытия', style: TextStyle(fontSize: 11, color: C.text4)),
                    ])),
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: fileColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(9)),
                      child: Icon(CupertinoIcons.arrow_up_right_square, size: 15, color: fileColor)),
                  ]),
                ),
              );
            }),
                SizedBox(height: 8),
              ],
              if (showDebug) Container(
                margin: EdgeInsets.only(top: 8, bottom: 8),
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('DEBUG: file_urls', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange)),
                  SizedBox(height: 4),
                  Text('list: $rawFromList', style: TextStyle(fontSize: 10, color: C.text4)),
                  Text('detail: $rawFromDetail', style: TextStyle(fontSize: 10, color: C.text4)),
                  if (hasError) Text('error: ${snap.error}', style: TextStyle(fontSize: 10, color: C.red)),
                ]),
              ),
            ]);
          },
        ),
        if (isTeacherOrAdmin && criteria.isNotEmpty) ...[
          SizedBox(height: 16),
          GestureDetector(
            onTap: () => setS(() { if (_expandedCriteria.contains(a['id'])) _expandedCriteria.remove(a['id']); else _expandedCriteria.add(a['id']); }),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Icon(CupertinoIcons.list_bullet, size: 16, color: Theme.of(context).colorScheme.primary),
                SizedBox(width: 8),
                Text('Критерии оценивания', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                SizedBox(width: 4),
                Text('(${criteria.length})', style: TextStyle(fontSize: 12, color: C.text4)),
                Spacer(),
                AnimatedRotation(turns: _expandedCriteria.contains(a['id']) ? 0.5 : 0.0, duration: Duration(milliseconds: 200),
                  child: Icon(CupertinoIcons.chevron_down, size: 20, color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
          ),
          AnimatedSize(duration: Duration(milliseconds: 300), curve: Curves.easeInOut,
            child: _expandedCriteria.contains(a['id']) ? Column(children: [
              SizedBox(height: 8),
              ...criteria.map((c) => Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
                child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (c['description'] != null && c['description'].toString().isNotEmpty)
                    Padding(padding: EdgeInsets.only(top: 4), child: Text(c['description'], style: TextStyle(fontSize: 12, color: C.text4))),
                ])),
                  Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(8)),
                    child: Text('${c['weight'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)))])))
            ]) : SizedBox.shrink(),
          ),
        ],
        if (sub?['grade'] != null) ...[
          SizedBox(height: 16),
          Container(padding: EdgeInsets.all(18), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: adaptiveBorder(context))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                RichText(text: TextSpan(children: [
                  TextSpan(text: '${sub['grade']['score']}', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, height: 1)),
                  TextSpan(text: ' / ${a['max_score']}', style: TextStyle(fontSize: 18, color: C.text4, fontWeight: FontWeight.w600)),
                ])),
                Spacer(),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${(sub['grade']['score'] / (a['max_score'] ?? 100) * 100).round()}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: adaptiveText1(context))),
                  SizedBox(height: 4),
                  Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(sub['grade']['graded_by'] == 'ai' ? CupertinoIcons.bolt_fill : CupertinoIcons.person, size: 14, color: Theme.of(context).colorScheme.primary),
                      SizedBox(width: 4),
                      Text(sub['grade']['graded_by'] == 'ai' ? 'ИИ-проверка' : 'Учитель', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                    ])),
                ]),
              ]),
              if (sub['grade']['feedback'] != null) ...[
                SizedBox(height: 14),
                Text('ФИДБЕК', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                SizedBox(height: 6),
                Text(sub['grade']['feedback'], style: TextStyle(fontSize: 14, color: adaptiveText1(context), height: 1.6)),
              ],
            ])),
          if (sub['grade']['criteria_scores'] != null) ...[
            SizedBox(height: 12),
            Text('ПО КРИТЕРИЯМ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
            SizedBox(height: 8),
            ...(() {
              List<dynamic> criteriaScores = [];
              try { criteriaScores = jsonDecode(sub['grade']['criteria_scores']); } catch (_) {
                if (sub['grade']['criteria_scores'] is List) criteriaScores = sub['grade']['criteria_scores'];
              }
              return criteriaScores.map<Widget>((cs) {
                final score = (cs['score'] ?? 0) as num;
                final maxScore = (cs['max_score'] ?? cs['max'] ?? cs['weight'] ?? 100) as num;
                final pct = maxScore > 0 ? score / maxScore : 0.0;
                return Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(cs['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: '${score.toInt()}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                        TextSpan(text: ' / ${maxScore.toInt()}', style: TextStyle(fontSize: 13, color: C.text4)),
                      ])),
                    ]),
                    if (cs['comment'] != null || cs['feedback'] != null)
                      Padding(padding: EdgeInsets.only(top: 6), child: Text(cs['comment'] ?? cs['feedback'] ?? '', style: TextStyle(fontSize: 13, color: C.text4, height: 1.5))),
                    SizedBox(height: 8),
                    ClipRRect(borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: pct.toDouble(), backgroundColor: adaptiveBorder(context), color: Theme.of(context).colorScheme.primary, minHeight: 4)),
                  ]));
              }).toList();
            })(),
          ],
        ],
        if (sub != null && sub['status'] == 'grading' && sub['grade'] == null) ...[
          SizedBox(height: 16),
          Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15))),
            child: Row(children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
              SizedBox(width: 12),
              Expanded(child: Text('ИИ проверяет вашу работу...', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500))),
            ])),
        ],
        if (sub != null && (sub['text_content'] != null || sub['file_urls'] != null)) ...[
          SizedBox(height: 16),
          Text('ВАШ ОТВЕТ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
          SizedBox(height: 6),
          if (sub['text_content'] != null && sub['text_content'].toString().isNotEmpty)
            Container(padding: EdgeInsets.all(12), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Text(sub['text_content'], style: TextStyle(fontSize: 13, height: 1.6), maxLines: 5, overflow: TextOverflow.ellipsis)),
          ...(() {
            List<String> urls = [];
            final raw = sub['file_urls'];
            if (raw is String && raw.isNotEmpty) {
              try { urls = (jsonDecode(raw) as List).map((f) => context.read<ApiService>().fixUrl(f.toString())).toList(); } catch (_) {}
            } else if (raw is List) {
              urls = raw.map((f) => context.read<ApiService>().fixUrl(f.toString())).toList();
            }
            if (urls.isEmpty) return <Widget>[];
            return [
              SizedBox(height: 8),
              ...urls.map((url) {
                final name = _fileDisplayName(url);
                final ext = name.split('.').last.toLowerCase();
                final icon = ext == 'pdf' ? CupertinoIcons.doc_text : ext == 'pptx' || ext == 'ppt' ? CupertinoIcons.film : ext == 'doc' || ext == 'docx' ? CupertinoIcons.doc_text : CupertinoIcons.doc;
                return GestureDetector(
                  onTap: () => widget.onOpenFile(url, name),
                  child: Container(margin: EdgeInsets.only(bottom: 6), padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary), SizedBox(width: 8),
                      Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                      Icon(CupertinoIcons.arrow_up_right_square, size: 14, color: Theme.of(context).colorScheme.primary),
                    ])),
                );
              }),
            ];
          })(),
        ],
        if (!isTeacherOrAdmin && sub != null && sub['status'] != 'graded' && sub['grade'] == null) ...[
          SizedBox(height: 12),
          GestureDetector(
            onTap: busy ? null : () async {
              setS(() => busy = true);
              try {
                await context.read<ApiService>().retractSubmission(sub['id']);
                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  showToast(context, 'Сдача отозвана — можно отправить заново');
                  widget.onRefresh();
                }
              } catch (_) {
                if (mounted && ctx.mounted) showToast(context, 'Ошибка', error: true);
              }
              if (ctx.mounted) setS(() => busy = false);
            },
            child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.arrow_counterclockwise, size: 14, color: C.text4),
                SizedBox(width: 6),
                Text(busy ? 'Отзыв...' : 'Отозвать и сдать заново', style: TextStyle(fontSize: 13, color: C.text4)),
              ])),
          ),
        ],
        if (!isTeacherOrAdmin && sub == null) ...[
          SizedBox(height: 20),
          Divider(),
          SizedBox(height: 12),
          Text('Отправить работу', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(height: 10),
          TextField(controller: tc, maxLines: 4, decoration: InputDecoration(hintText: 'Текст работы или ссылка (необязательно)...')),
          SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
              if (result != null) setS(() => pickedFiles = result.files);
            },
            child: Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3), width: 1.5)),
              child: Row(children: [
                Icon(CupertinoIcons.paperclip, color: Theme.of(context).colorScheme.primary, size: 20),
                SizedBox(width: 10),
                Expanded(child: Text(pickedFiles.isEmpty ? 'Прикрепить файлы' : 'Файлов выбрано: ${pickedFiles.length}', style: TextStyle(fontSize: 14, color: pickedFiles.isEmpty ? C.text4 : Theme.of(context).colorScheme.primary, fontWeight: pickedFiles.isEmpty ? FontWeight.normal : FontWeight.w600))),
                Icon(CupertinoIcons.chevron_right, color: C.text4, size: 18),
              ])),
          ),
          if (pickedFiles.isNotEmpty) ...[
            SizedBox(height: 8),
            ...pickedFiles.map((f) => Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(CupertinoIcons.doc, size: 14, color: Theme.of(context).colorScheme.primary),
                SizedBox(width: 6),
                Expanded(child: Text(f.name, style: TextStyle(fontSize: 12, color: C.text3), overflow: TextOverflow.ellipsis)),
                GestureDetector(onTap: () => setS(() => pickedFiles.removeWhere((x) => x.name == f.name)),
                  child: Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
              ]),
            )),
          ],
          SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: busy ? null : () async {
              if (tc.text.trim().isEmpty && pickedFiles.isEmpty) {
                showToast(context, 'Добавьте текст или прикрепите файлы', error: true);
                return;
              }
              setS(() => busy = true);
              try {
                final api = context.read<ApiService>();
                final fileUrls = <String>[];
                for (final pf in pickedFiles) {
                  if (pf.path != null) {
                    try {
                      final res = await api.uploadFile(pf.path!, pf.name);
                      final url = res['url'] ?? res['file_url'] ?? res['path'];
                      if (url != null) fileUrls.add('${url}#${Uri.encodeComponent(pf.name)}');
                    } catch (_) {}
                  }
                }
                await api.submitAssignment(a['id'], {
                  if (tc.text.trim().isNotEmpty) 'text_content': tc.text.trim(),
                  if (fileUrls.isNotEmpty) 'file_urls': fileUrls,
                });
                if (mounted && ctx.mounted) {
                  Navigator.pop(ctx);
                  showToast(context, 'Работа отправлена!');
                  widget.onRefresh();
                }
              } catch (_) {
                if (mounted && ctx.mounted) showToast(context, 'Ошибка отправки', error: true);
              }
              if (ctx.mounted) setS(() => busy = false);
            },
            child: busy ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Отправить'),
          )),
        ],
        if (isTeacherOrAdmin) ...[
          SizedBox(height: 20),
          Divider(height: 1, color: adaptiveBorder(context)),
          SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              icon: Icon(CupertinoIcons.pencil, size: 16),
              label: Text('Редактировать'),
              onPressed: () { Navigator.pop(ctx); widget.onEditAssignment(a); },
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
            )),
            SizedBox(width: 10),
            OutlinedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await showCupertinoDialog<bool>(context: context, builder: (d) => CupertinoAlertDialog(
                  title: const Text('Удалить задание?'),
                  content: const Text('Это действие нельзя отменить'),
                  actions: [
                    CupertinoDialogAction(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                    CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                  ],
                ));
                if (ok == true && mounted) {
                  try {
                    await context.read<ApiService>().deleteAssignment(a['id']);
                    if (mounted) { widget.onRefresh(); showToast(context, 'Задание удалено'); }
                  } catch (_) {
                    if (mounted) showToast(context, 'Ошибка', error: true);
                  }
                }
              },
              style: OutlinedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12), side: BorderSide(color: C.red.withValues(alpha: 0.5))),
              child: Icon(CupertinoIcons.trash, size: 18, color: C.red),
            ),
          ]),
          SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
            icon: Icon(CupertinoIcons.list_bullet, size: 18),
            label: Text('Просмотр работ'),
            onPressed: () => _viewSubs(a['id']),
            style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 12)),
          )),
        ],
        SizedBox(height: 24),
      ])),
          ]),
        ),
      );
      }),
    );
  }

  void _viewSubs(int aId) async {
    try {
      final subs = await context.read<ApiService>().getSubmissions(aId);
      if (!mounted) return;
      showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          String search = '';
          dynamic selectedSub;
          bool grading = false;
          bool gradingAll = false;
          int gradingDone = 0;
          int gradingTotal = 0;
          return StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (ctx, sc) {
            // Recomputed on every rebuild so stats stay fresh after batch grading
            final graded = subs.where((s) => s['status'] == 'graded').length;
            final pending = subs.length - graded;
            if (selectedSub != null) {
              final name = selectedSub['student_name'] ?? '#${selectedSub['student_id']}';
              final initials = name.length >= 2 ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase() : name[0].toUpperCase();
              final grade = selectedSub['grade'];
              final score = grade?['score'];
              final feedback = grade?['feedback'];
              final criteria = grade?['criteria'] as List<dynamic>? ?? [];
              List<String> submittedFileUrls = [];
              final rawUrls = selectedSub['file_urls'];
              if (rawUrls is List) {
                submittedFileUrls = rawUrls.map((f) => context.read<ApiService>().fixUrl(f.toString())).toList();
              } else if (rawUrls is String && rawUrls.isNotEmpty) {
                try { submittedFileUrls = (jsonDecode(rawUrls) as List).map((f) => context.read<ApiService>().fixUrl(f.toString())).toList(); } catch (_) {}
              }
              return ListView(controller: sc, padding: EdgeInsets.all(20), children: [
                Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
                GestureDetector(onTap: () => setS(() => selectedSub = null),
                  child: Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(CupertinoIcons.chevron_left, size: 16, color: C.text4), SizedBox(width: 6), Text('Назад к списку', style: TextStyle(fontSize: 13, color: C.text4))]))),
                SizedBox(height: 16),
                Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), child: Text(initials, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 14))),
                  SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(selectedSub['submitted_at'] != null ? _fmtDate(selectedSub['submitted_at']) : '', style: TextStyle(fontSize: 12, color: C.text4)),
                  ])),
                ]),
                if (selectedSub['text_content'] != null || submittedFileUrls.isNotEmpty) ...[
                  SizedBox(height: 16),
                  Text('РАБОТА СТУДЕНТА', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                  SizedBox(height: 8),
                  if (selectedSub['text_content'] != null) Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: Text(selectedSub['text_content'], style: TextStyle(fontSize: 13))),
                  ...submittedFileUrls.map((url) {
                    final name = _fileDisplayName(url);
                    final ext = name.split('.').last.toLowerCase();
                    final icon = ext == 'pdf' ? CupertinoIcons.doc_text : ext == 'pptx' || ext == 'ppt' ? CupertinoIcons.film : ext == 'doc' || ext == 'docx' ? CupertinoIcons.doc_text : CupertinoIcons.doc;
                    return GestureDetector(
                      onTap: () => widget.onOpenFile(url, name),
                      child: Container(padding: EdgeInsets.all(12), margin: EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary), SizedBox(width: 8),
                          Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                          Icon(CupertinoIcons.arrow_up_right_square, size: 14, color: Theme.of(context).colorScheme.primary),
                        ])));
                  }),
                ],
                if (score != null) ...[
                  SizedBox(height: 20),
                  Container(padding: EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: '$score', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                          TextSpan(text: ' / 100', style: TextStyle(fontSize: 16, color: C.text4)),
                        ])),
                        Spacer(),
                        Container(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(CupertinoIcons.bolt_fill, size: 14, color: Theme.of(context).colorScheme.primary), SizedBox(width: 4), Text('ИИ-проверка', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))])),
                      ]),
                      if (feedback != null) ...[
                        SizedBox(height: 12),
                        Text('ФИДБЕК', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                        SizedBox(height: 6),
                        Text(feedback, style: TextStyle(fontSize: 14, height: 1.6)),
                      ],
                    ])),
                  if (criteria.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Text('ПО КРИТЕРИЯМ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                    SizedBox(height: 8),
                    ...criteria.map((c) => Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(14)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c['name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '${c['score'] ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                            TextSpan(text: ' / ${c['max_score'] ?? c['weight'] ?? 0}', style: TextStyle(fontSize: 13, color: C.text4)),
                          ])),
                        ]),
                        if (c['feedback'] != null) Padding(padding: EdgeInsets.only(top: 6), child: Text(c['feedback'], style: TextStyle(fontSize: 13, color: C.text4, height: 1.5))),
                      ]))),
                  ],
                  SizedBox(height: 16),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      try {
                        await context.read<ApiService>().aiGrade(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, 'Переоценено!');
                      } catch (e) {
                        if (!mounted || !ctx.mounted) return;
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? 'Нет критериев оценивания' : 'Ошибка оценки';
                        showToast(context, msg, error: true);
                      }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('ИИ оценивает...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Перепроверить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                  )),
                ] else ...[
                  SizedBox(height: 20),
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      try {
                        await context.read<ApiService>().aiGrade(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, 'Оценено!');
                      } catch (e) {
                        if (!mounted || !ctx.mounted) return;
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? 'Нет критериев оценивания' : 'Ошибка оценки';
                        showToast(context, msg, error: true);
                      }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          SizedBox(width: 12),
                          Text('ИИ оценивает...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Оценить ИИ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                  )),
                ],
                SizedBox(height: 24),
              ]);
            }
            final filtered = subs.where((s) => search.isEmpty || (s['student_name'] ?? '').toLowerCase().contains(search.toLowerCase())).toList();
            return ListView(controller: sc, padding: EdgeInsets.all(20), children: [
              Center(child: Container(width: 40, height: 4, margin: EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
              Row(children: [
                _statBox('${subs.length}', 'Всего', adaptiveText1(context)),
                SizedBox(width: 8),
                _statBox('$graded', 'Проверено', Theme.of(context).colorScheme.primary),
                SizedBox(width: 8),
                _statBox('$pending', 'Ожидают', C.red),
              ]),
              // Batch AI grading button
              if (pending > 0) ...[
                SizedBox(height: 14),
                SizedBox(width: double.infinity, height: 50,
                  child: ElevatedButton(
                    onPressed: gradingAll ? null : () async {
                      final ungraded = subs.where((s) => s['status'] != 'graded').toList();
                      setS(() { gradingAll = true; gradingDone = 0; gradingTotal = ungraded.length; });
                      for (final s in ungraded) {
                        try {
                          await context.read<ApiService>().aiGrade(s['id']);
                          if (!mounted || !ctx.mounted) return;
                          setS(() => gradingDone++);
                        } catch (_) {}
                      }
                      if (!mounted || !ctx.mounted) return;
                      try {
                        final updated = await context.read<ApiService>().getSubmissions(aId);
                        subs.clear();
                        subs.addAll(updated);
                      } catch (_) {}
                      if (mounted && ctx.mounted) setS(() { gradingAll = false; });
                      if (mounted) showToast(context, 'Проверено $gradingDone из $gradingTotal');
                    },
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: gradingAll ? adaptiveSurface2(context) : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (gradingAll) ...[
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                        SizedBox(width: 12),
                        Text('Проверено $gradingDone / $gradingTotal...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      ] else ...[
                        Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Проверить все ИИ ($pending)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ]),
                  )),
              ],
              SizedBox(height: 16),
              TextField(decoration: InputDecoration(hintText: 'Поиск по ФИО студента...', prefixIcon: Icon(CupertinoIcons.search, size: 18, color: C.text4), contentPadding: EdgeInsets.symmetric(vertical: 10)),
                onChanged: (v) => setS(() => search = v)),
              SizedBox(height: 12),
              ...filtered.map((s) {
                final name = s['student_name'] ?? s['student_email'] ?? '#${s['student_id']}';
                final initials = name.length >= 2 ? '${name[0]}${name.split(' ').length > 1 ? name.split(' ').last[0] : name[1]}'.toUpperCase() : name[0].toUpperCase();
                final score = s['grade']?['score'];
                final isGraded = s['status'] == 'graded';
                return GestureDetector(onTap: () => setS(() => selectedSub = s),
                  child: Container(margin: EdgeInsets.only(bottom: 8), padding: EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16)),
                    child: Row(children: [
                      CircleAvatar(radius: 20, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), child: Text(initials, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 13))),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text(s['submitted_at'] != null ? _fmtDate(s['submitted_at']) : '', style: TextStyle(fontSize: 11, color: C.text4)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (score != null) Text('$score/100', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary))
                        else Text('—', style: TextStyle(fontSize: 16, color: C.text4)),
                        Text(isGraded ? 'Оценено' : 'Ожидает', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isGraded ? Theme.of(context).colorScheme.primary : C.yellow)),
                      ]),
                    ])));
              }),
            ]);
          }));
        });
    } catch (_) { showToast(context, 'Ошибка загрузки', error: true); }
  }
}
