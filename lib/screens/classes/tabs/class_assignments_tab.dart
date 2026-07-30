import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/l10n_provider.dart';
import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/initials.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../class_detail_utils.dart';
import '../assignment_detail_screen.dart';
import '../../../utils/dates.dart';
import '../../../utils/haptics.dart';

class ClassAssignmentsTab extends StatefulWidget {
  final List<dynamic> assignments;
  final List<dynamic> mySubs;
  final Map<String, dynamic> rating;
  final bool isTeacher;
  final int classId;
  final bool isLoading;
  final bool viewOnly;
  final int? cohortId;
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
    this.viewOnly = false,
    this.cohortId,
    required this.onRefresh,
    required this.onEditAssignment,
    required this.onOpenFile,
  });

  @override
  State<ClassAssignmentsTab> createState() => _ClassAssignmentsTabState();
}

List<String> _parseStringList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.map((e) => e.toString()).toList();
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
  }
  return [];
}

class _ClassAssignmentsTabState extends State<ClassAssignmentsTab> {
  static const _checkSteps = ['check_step_1', 'check_step_2', 'check_step_3', 'check_step_4', 'check_step_5'];

  dynamic _subFor(int aId) => widget.mySubs.firstWhere((s) => s['assignment_id'] == aId, orElse: () => null);

  String _fmtDate(String? d) => fmtDate(d);

  static final _fileUrlRe = fileUrlRe;
  static final _mdFileRe = mdFileRe;
  static final _extraNewlinesRe = RegExp(r'\n{3,}');

  String _fileDisplayName(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
    } catch (_) { return url; }
  }

  String _cleanContent(String content) {
    return content
        .replaceAll(_mdFileRe, '')
        .replaceAll(_fileUrlRe, '')
        .replaceAll(_extraNewlinesRe, '\n\n')
        .trim();
  }

  Widget _statBox(String val, String label, Color color) => Expanded(child: Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2))),
    child: Column(children: [Text(val, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)), const SizedBox(height: 2), Text(label, style: const TextStyle(fontSize: 11, color: C.text4))])));

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    if (widget.isLoading) return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2.5));
    final surface = Theme.of(context).colorScheme.surface;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final avg = (widget.rating['avg_score'] ?? 0).round();
    final pct = (widget.rating['avg_percent'] ?? 0).round();

    final subMap = <int, dynamic>{};
    for (final s in widget.mySubs) {
      subMap[(s['assignment_id'] as num).toInt()] = s;
    }
    // Ленивый список: карточки заданий строятся по мере скролла, а не все сразу
    // (при 30–50 заданиях жадный ListView даёт заметный лаг на открытии вкладки).
    final headers = <Widget>[
      if (!widget.isTeacher && widget.rating.isNotEmpty) Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF006475), Theme.of(context).colorScheme.primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(AppRadii.tile),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('your_rating'), style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 8),
              RichText(text: TextSpan(children: [
                TextSpan(text: '$avg', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1)),
                const TextSpan(text: ' /100', style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w600)),
              ])),
              const SizedBox(height: 8),
              ClipRRect(borderRadius: BorderRadius.circular(AppRadii.chip), child: LinearProgressIndicator(
                value: avg / 100, backgroundColor: Colors.white24, color: Colors.white, minHeight: 4)),
              const SizedBox(height: 4),
              Text('${l.t('performance')}: $pct%', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
            ]),
          )),
          const SizedBox(width: 10),
          Expanded(child: Builder(builder: (_) {
            final now = DateTime.now();
            final upcoming = widget.assignments.where((a) {
              if (a['deadline'] == null) return false;
              final dl = parseServerDate(a['deadline']);
              if (dl == null) return false;
              final sub = _subFor(a['id']);
              return dl.isAfter(now) && (sub == null || sub['status'] != 'graded');
            }).toList();
            // toString перед сравнением: если сервер отдаст дату числом,
            // compareTo на dynamic упадёт в рантайме.
            upcoming.sort((a, b) =>
                '${a['deadline'] ?? ''}'.compareTo('${b['deadline'] ?? ''}'));
            if (upcoming.isEmpty) {
              return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('next_deadline'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                const SizedBox(height: 16),
                const Center(child: Icon(CupertinoIcons.checkmark_circle, size: 32, color: C.green)),
                const SizedBox(height: 8),
                Center(child: Text(l.t('all_submitted'), style: const TextStyle(fontSize: 13, color: C.green, fontWeight: FontWeight.w600))),
              ]));
            }
            final next = upcoming.first;
            // Без force unwrap: связь с фильтром выше неявная и легко ломается
            // при рефакторинге, а падение здесь — красный экран внутри build.
            final dl = parseServerDate(next['deadline']);
            if (dl == null) return const SizedBox.shrink();
            final diff = dl.difference(now);
            final days = diff.inDays;
            final hours = diff.inHours % 24;
            final months = l.t('months_short').split(',');
            final remaining = days > 0
                ? '$days ${l.t('days_short')} $hours ${l.t('hours_short')}'
                : '$hours ${l.t('hours_short')} ${diff.inMinutes % 60} ${l.t('minutes_short')}';
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: adaptiveBorder(context))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('next_deadline'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 48, height: 56,
                    decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(months[dl.month - 1], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary, letterSpacing: 1)),
                      Text('${dl.day}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary, height: 1.1)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Две строки: названия вида «Лабораторная работа 5» в одну
                    // строку не помещаются и обрезаются до «Лаборатор…».
                    Text(next['title'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${l.t('remaining')}: $remaining', style: TextStyle(fontSize: 11, color: days <= 1 ? C.red : Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
                  ])),
                ]),
              ]),
            );
          })),
        ])),
      ),
      Text(l.t('assignments'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      if (widget.assignments.isEmpty) Container(padding: const EdgeInsets.symmetric(vertical: 52), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.16), Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)]), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.doc_text, size: 36, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(height: 18),
        Text(l.t('no_assignments'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Text(widget.isTeacher ? l.t('create_first_assignment') : l.t('no_assignments_yet'),
          style: const TextStyle(fontSize: 13, color: C.text4)),
      ]))),
    ];
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
      itemCount: headers.length + widget.assignments.length,
      itemBuilder: (ctx, index) {
        if (index < headers.length) return headers[index];
        final i = index - headers.length;
        final a = widget.assignments[i];
        final sub = subMap[(a['id'] as num).toInt()];
        final status = sub?['status'];
        final grade = sub?['grade'];
        final isGraded = status == 'graded';
        final isSubmitted = status == 'submitted';
        final isNeedsReview = status == 'needs_review';
        final deadline = a['deadline'];
        final isLate = deadline != null && parseServerDate(deadline)?.isBefore(DateTime.now()) == true && sub == null;
        // Раньше считался дважды на карточку (в условии isNotEmpty и в самом
        // Text) — оба реплейса на каждую видимую карточку при каждом скролле.
        final desc = a['description'] != null ? _cleanContent(a['description'].toString()) : '';

        final showBadge = isGraded || isNeedsReview || isSubmitted || isLate;
        Color statusColor = isGraded ? C.green : isNeedsReview ? C.amber : isSubmitted ? Theme.of(context).colorScheme.primary : C.red;
        String statusText = isGraded ? l.t('graded') : isNeedsReview ? l.t('needs_review') : isSubmitted ? l.t('submitted') : l.t('overdue');
        IconData statusIcon = isGraded ? CupertinoIcons.checkmark_circle_fill : isNeedsReview ? CupertinoIcons.exclamationmark_triangle : isSubmitted ? CupertinoIcons.arrow_up_doc : CupertinoIcons.clock;

        return TweenAnimationBuilder<double>(
          key: ValueKey('asgn_${a['id']}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 220 + i.clamp(0, 5) * 50),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: child)),
          child: RepaintBoundary(child: Tappable(
            onTap: () => _showAssignment(a, sub),
            scale: 0.98,
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(AppRadii.card),
                boxShadow: cardShadow(isDark),
              ),
              child: Column(children: [
                Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Text(a['title'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    if (widget.isTeacher) Tappable(
                      onTap: () => _showAssignmentActions(a),
                      child: Container(width: 30, height: 30, alignment: Alignment.center, margin: const EdgeInsets.only(left: 2),
                        child: const Icon(CupertinoIcons.ellipsis, size: 18, color: C.text4)),
                    ),
                  ]),
                  if (desc.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text(desc, style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 12, children: [
                    if (deadline != null) Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(CupertinoIcons.calendar, size: 12, color: C.text4), const SizedBox(width: 4),
                      Text(_fmtDate(deadline), style: const TextStyle(fontSize: 13, color: C.text4, fontWeight: FontWeight.w500)),
                    ]),
                    if (grade != null) Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(CupertinoIcons.checkmark_circle_fill, size: 12, color: C.green), const SizedBox(width: 3),
                      Text('${grade['score']}/${a['max_score']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: C.green)),
                    ]),
                  ]),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(
                    color: adaptiveSurface2(context).withValues(alpha: 0.45),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
                  ),
                  child: Row(children: [
                    if (showBadge) Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.chip)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(statusIcon, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: statusColor)),
                      ]),
                    ),
                    const Spacer(),
                    Row(children: [
                      Text(l.t('open'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(width: 3),
                      Icon(CupertinoIcons.chevron_right, size: 13, color: Theme.of(context).colorScheme.primary),
                    ]),
                  ]),
                ),
              ]),
            ),
          )),
        );
      },
    ));
  }

  void _deleteAssignment(dynamic a) async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(context,
      title: l.t('delete_assignment_q'),
      message: l.t('delete_irreversible'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
    if (ok != true || !mounted) return;
    try {
      await context.read<ApiService>().deleteAssignment(a['id']);
      if (mounted) { widget.onRefresh(); showToast(context, l.t('assignment_deleted')); }
    } catch (_) {
      if (mounted) showToast(context, l.t('error_generic'), error: true);
    }
  }

  void _showAssignmentActions(dynamic a) {
    final l = context.read<L10n>();
    showAppActionSheet(context,
      actions: [
        AppActionSheetAction(icon: CupertinoIcons.pencil, label: l.t('edit'), onTap: () => widget.onEditAssignment(a)),
        AppActionSheetAction(icon: CupertinoIcons.trash, label: l.t('delete'), destructive: true, onTap: () => _deleteAssignment(a)),
      ],
      cancelText: l.t('cancel'),
    );
  }

  void _showAssignment(dynamic a, dynamic sub) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(
      assignment: a,
      submission: sub,
      isTeacher: widget.isTeacher,
      viewOnly: widget.viewOnly,
      onRefresh: widget.onRefresh,
      onOpenFile: (url, name) => widget.onOpenFile(url, name),
      onEditAssignment: widget.onEditAssignment,
      onViewSubmissions: (asg) => _viewSubs((asg['id'] as num).toInt()),
    )));
  }

  void _viewSubs(int aId) async {
    final l = context.read<L10n>();
    final assignmentMaxScore = (widget.assignments.firstWhere((x) => (x['id'] as num).toInt() == aId, orElse: () => {})['max_score'] as num?) ?? 100;
    try {
      final subs = await context.read<ApiService>().getSubmissions(aId, cohortId: widget.cohortId);
      if (!mounted) return;
      showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) {
          String search = '';
          dynamic selectedSub;
          bool grading = false;
          bool gradingAll = false;
          int gradingDone = 0;
          int gradingTotal = 0;
          // Проверка ИИ — единственный блокирующий запрос без стадий на бэкенде,
          // поэтому прогресс симулируем на клиенте (тот же текст, что на Web).
          int checkStepIdx = 0;
          Timer? checkStepTimer;
          void startCheckSteps(void Function(void Function()) setS) {
            checkStepIdx = 0;
            checkStepTimer?.cancel();
            checkStepTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
              if (checkStepIdx < _checkSteps.length - 1) setS(() => checkStepIdx++);
            });
          }
          void stopCheckSteps() { checkStepTimer?.cancel(); checkStepTimer = null; }
          return StatefulBuilder(builder: (ctx, setS) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (ctx, sc) {
            final graded = subs.where((s) => s['status'] == 'graded').length;
            final pending = subs.length - graded;
            if (selectedSub != null) {
              final name = (selectedSub['student_name'] ?? '#${selectedSub['student_id']}').toString();
              final initials = initialsFrom(name);
              final grade = selectedSub['grade'];
              final score = grade?['score'];
              final feedback = grade?['feedback'];
              final criteria = parseCriteriaScores(grade?['criteria_scores']);
              List<String> submittedFileUrls = [];
              final rawUrls = selectedSub['file_urls'];
              if (rawUrls is List) {
                submittedFileUrls = rawUrls.map((f) => context.read<ApiService>().fixUrl(f.toString())).toList();
              } else if (rawUrls is String && rawUrls.isNotEmpty) {
                try { submittedFileUrls = (jsonDecode(rawUrls) as List).map((f) => context.read<ApiService>().fixUrl(f.toString())).toList(); } catch (_) {}
              }
              return ListView(controller: sc, padding: const EdgeInsets.all(20), children: [
                Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(AppRadii.chip)))),
                Tappable(onTap: () => setS(() => selectedSub = null),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(CupertinoIcons.chevron_left, size: 16, color: C.text4), const SizedBox(width: 6), Text(l.t('back_to_list'), style: const TextStyle(fontSize: 13, color: C.text4))]))),
                const SizedBox(height: 16),
                Row(children: [
                  CircleAvatar(radius: 22, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), child: Text(initials, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 15))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    Text(selectedSub['submitted_at'] != null ? _fmtDate(selectedSub['submitted_at']) : '', style: const TextStyle(fontSize: 13, color: C.text4)),
                  ])),
                ]),
                if (selectedSub['text_content'] != null || submittedFileUrls.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(l.t('student_work'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  if (selectedSub['text_content'] != null) Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Text(selectedSub['text_content'], style: const TextStyle(fontSize: 13))),
                  ...submittedFileUrls.map((url) {
                    final name = _fileDisplayName(url);
                    final ext = name.split('.').last.toLowerCase();
                    final icon = ext == 'pdf' ? CupertinoIcons.doc_text : ext == 'pptx' || ext == 'ppt' ? CupertinoIcons.film : ext == 'doc' || ext == 'docx' ? CupertinoIcons.doc_text : CupertinoIcons.doc;
                    return Tappable(
                      onTap: () => widget.onOpenFile(url, name),
                      child: Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(AppRadii.tile)),
                        child: Row(children: [
                          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 8),
                          Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary), overflow: TextOverflow.ellipsis)),
                          Icon(CupertinoIcons.arrow_up_right_square, size: 14, color: Theme.of(context).colorScheme.primary),
                        ])));
                  }),
                ],
                if (selectedSub['status'] == 'needs_review') ...[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: C.amber.withValues(alpha: 0.3))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.t('status_needs_review_label'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.amber)),
                      if (score != null) ...[
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(l.t('suggested_score_label'), style: const TextStyle(fontSize: 13, color: C.text4)),
                          Text('$score / $assignmentMaxScore', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ]),
                      ],
                      if (selectedSub['ai_confidence'] != null) ...[
                        const SizedBox(height: 6),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(l.t('confidence_label'), style: const TextStyle(fontSize: 13, color: C.text4)),
                          Text('${selectedSub['ai_confidence']}%', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                        ]),
                      ],
                      if (_parseStringList(selectedSub['ai_review_reasons']).isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(l.t('review_reasons_label'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                        const SizedBox(height: 6),
                        for (final r in _parseStringList(selectedSub['ai_review_reasons']))
                          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $r', style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4))),
                      ],
                      if (feedback != null || criteria.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(l.t('ai_analysis_label'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                        if (feedback != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(feedback, style: const TextStyle(fontSize: 13, height: 1.5))),
                        for (final c in criteria) Container(
                          margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(c['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                              Text('${c['score'] ?? 0} / ${c['max'] ?? c['max_score'] ?? c['weight'] ?? 0}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                            if ((c['comment'] ?? c['feedback']) != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c['comment'] ?? c['feedback'], style: const TextStyle(fontSize: 13, color: C.text4, height: 1.4))),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: ElevatedButton(
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: (grade == null || grading) ? null : () async {
                        setS(() => grading = true);
                        try {
                          final updatedGrade = await context.read<ApiService>().gradeSubmission(
                            selectedSub['id'],
                            score: score,
                            feedback: feedback,
                            criteriaScores: criteria.isNotEmpty ? criteria : null,
                          );
                          if (!mounted || !ctx.mounted) return;
                          // Финальную оценку теперь ставит человек — старая уверенность
                          // ИИ (если сдача была needs_review) больше не относится к делу
                          // и вводит в заблуждение рядом с новым баллом.
                          setS(() { selectedSub = {...selectedSub, 'grade': updatedGrade, 'status': 'graded', 'ai_confidence': null, 'ai_review_reasons': null}; grading = false; });
                          showToast(context, '${l.t('grade_saved')}: ${updatedGrade['score']} / $assignmentMaxScore');
                        } catch (e) {
                          if (!mounted || !ctx.mounted) return;
                          setS(() => grading = false);
                          showToast(context, l.t('grade_error'), error: true);
                        }
                      },
                      child: grading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(l.t('confirm_suggested'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(
                      onPressed: () => _showManualGradeDialog(ctx, selectedSub, assignmentMaxScore, (updated) => setS(() => selectedSub = updated)),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(l.t('change_score'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                    )),
                  ]),
                ] else if (score != null) ...[
                  const SizedBox(height: 20),
                  Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        RichText(text: TextSpan(children: [
                          TextSpan(text: '$score', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
                          const TextSpan(text: ' / 100', style: TextStyle(fontSize: 17, color: C.text4)),
                        ])),
                        const Spacer(),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.card)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(CupertinoIcons.bolt_fill, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text(l.t('ai_check'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))])),
                      ]),
                      if (feedback != null) ...[
                        const SizedBox(height: 12),
                        Text(l.t('feedback'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                        const SizedBox(height: 6),
                        Text(feedback, style: const TextStyle(fontSize: 15, height: 1.6)),
                      ],
                    ])),
                  if (criteria.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(l.t('by_criteria'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    ...criteria.map((c) => Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Theme.of(ctx).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(c['name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '${c['score'] ?? 0}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                            TextSpan(text: ' / ${c['max'] ?? c['max_score'] ?? c['weight'] ?? 0}', style: const TextStyle(fontSize: 13, color: C.text4)),
                          ])),
                        ]),
                        if ((c['comment'] ?? c['feedback']) != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c['comment'] ?? c['feedback'], style: const TextStyle(fontSize: 13, color: C.text4, height: 1.5))),
                      ]))),
                  ],
                  const SizedBox(height: 16),
                  ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 50), child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      startCheckSteps(setS);
                      try {
                        final result = await context.read<ApiService>().aiGrade(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, result['status'] == 'needs_review' ? l.t('needs_review_toast') : l.t('regraded'));
                      } catch (e) {
                        if (!mounted || !ctx.mounted) return;
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? l.t('no_criteria') : l.t('grade_error');
                        showToast(context, msg, error: true);
                      } finally { stopCheckSteps(); }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text(l.t(_checkSteps[checkStepIdx]), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(l.t('recheck_ai'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                  )),
                  const SizedBox(height: 10),
                  _manualGradeAndDeleteRow(ctx, selectedSub, assignmentMaxScore, (updated) => setS(() => selectedSub = updated), () {
                    subs.removeWhere((s) => s['id'] == selectedSub['id']);
                    setS(() => selectedSub = null);
                    widget.onRefresh();
                  }),
                ] else ...[
                  const SizedBox(height: 20),
                  ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 50), child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: grading ? null : () async {
                      setS(() => grading = true);
                      startCheckSteps(setS);
                      try {
                        final result = await context.read<ApiService>().aiGrade(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        final updated = await context.read<ApiService>().getSubmission(selectedSub['id']);
                        if (!mounted || !ctx.mounted) return;
                        setS(() { selectedSub = updated; grading = false; });
                        showToast(context, result['status'] == 'needs_review' ? l.t('needs_review_toast') : l.t('graded_ok'));
                      } catch (e) {
                        if (!mounted || !ctx.mounted) return;
                        setS(() => grading = false);
                        final msg = e.toString().contains('criteria') ? l.t('no_criteria') : l.t('grade_error');
                        showToast(context, msg, error: true);
                      } finally { stopCheckSteps(); }
                    },
                    child: grading
                      ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text(l.t(_checkSteps[checkStepIdx]), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(l.t('grade_ai'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                  )),
                  const SizedBox(height: 10),
                  _manualGradeAndDeleteRow(ctx, selectedSub, assignmentMaxScore, (updated) => setS(() => selectedSub = updated), () {
                    subs.removeWhere((s) => s['id'] == selectedSub['id']);
                    setS(() => selectedSub = null);
                    widget.onRefresh();
                  }),
                ],
                const SizedBox(height: 24),
              ]);
            }
            final filtered = subs.where((s) => search.isEmpty || (s['student_name'] ?? '').toLowerCase().contains(search.toLowerCase())).toList();
            // Ленивый список: у популярного задания это может быть 50–100+ работ.
            final gradeHeaders = <Widget>[
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(AppRadii.chip)))),
              Row(children: [
                _statBox('${subs.length}', l.t('total'), adaptiveText1(context)),
                const SizedBox(width: 8),
                _statBox('$graded', l.t('checked'), Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                _statBox('$pending', l.t('pending'), C.red),
              ]),
              if (pending > 0) ...[
                const SizedBox(height: 14),
                ConstrainedBox(constraints: const BoxConstraints(minWidth: double.infinity, minHeight: 50), child: ElevatedButton(
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
                        final updated = await context.read<ApiService>().getSubmissions(aId, cohortId: widget.cohortId);
                        subs.clear();
                        subs.addAll(updated);
                      } catch (_) {}
                      if (mounted && ctx.mounted) setS(() { gradingAll = false; });
                      if (mounted) showToast(context, '${l.t('grade_progress')} $gradingDone / $gradingTotal');
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: gradingAll ? adaptiveSurface2(context) : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (gradingAll) ...[
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(width: 12),
                        Text('${l.t('grade_progress')} $gradingDone / $gradingTotal...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                      ] else ...[
                        const Icon(CupertinoIcons.bolt_fill, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text('${l.t('grade_all_ai')} ($pending)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ]),
                  )),
              ],
              const SizedBox(height: 16),
              TextField(decoration: InputDecoration(hintText: l.t('search_student'), prefixIcon: const Icon(CupertinoIcons.search, size: 18, color: C.text4), contentPadding: const EdgeInsets.symmetric(vertical: 10)),
                onChanged: (v) => setS(() => search = v)),
              const SizedBox(height: 12),
            ];
            return ListView.builder(
              controller: sc,
              padding: const EdgeInsets.all(20),
              itemCount: gradeHeaders.length + filtered.length,
              itemBuilder: (ctx, index) {
                if (index < gradeHeaders.length) return gradeHeaders[index];
                final s = filtered[index - gradeHeaders.length];
                final name = (s['student_name'] ?? s['student_email'] ?? '#${s['student_id']}').toString();
                final initials = initialsFrom(name);
                final score = s['grade']?['score'];
                final isGraded = s['status'] == 'graded';
                final isNeedsReview = s['status'] == 'needs_review';
                return Tappable(onTap: () => setS(() => selectedSub = s),
                  child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Row(children: [
                      CircleAvatar(radius: 20, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15), child: Text(initials, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 13))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(s['submitted_at'] != null ? _fmtDate(s['submitted_at']) : '', style: const TextStyle(fontSize: 11, color: C.text4)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        if (score != null) Text('$score/100', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary))
                        else const Text('—', style: TextStyle(fontSize: 17, color: C.text4)),
                        Text(isGraded ? l.t('graded_one') : isNeedsReview ? l.t('needs_review') : l.t('pending_one'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isGraded ? Theme.of(context).colorScheme.primary : isNeedsReview ? C.amber : C.yellow)),
                      ]),
                    ])));
              },
            );
          }));
        });
    } catch (_) { showToast(context, l.t('error_loading'), error: true); }
  }

  Widget _manualGradeAndDeleteRow(BuildContext ctx, dynamic sub, num maxScore, void Function(dynamic updated) onGraded, VoidCallback onDeleted) {
    final l = context.read<L10n>();
    return Row(children: [
      Expanded(child: OutlinedButton.icon(
        onPressed: () => _showManualGradeDialog(ctx, sub, maxScore, onGraded),
        icon: const Icon(CupertinoIcons.pencil, size: 16),
        label: Text(l.t('grade_manually'), style: const TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
      )),
      const SizedBox(width: 10),
      Tappable(
        onTap: () => _confirmDeleteSubmission(ctx, sub, onDeleted),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: C.red.withValues(alpha: 0.5))),
          child: const Icon(CupertinoIcons.trash, size: 18, color: C.red),
        ),
      ),
    ]);
  }

  Future<void> _showManualGradeDialog(BuildContext ctx, dynamic sub, num maxScore, void Function(dynamic updated) onGraded) async {
    final l = context.read<L10n>();
    final existingScore = sub['grade']?['score'];
    final scoreC = TextEditingController(text: existingScore != null ? '$existingScore' : '');
    final feedbackC = TextEditingController(text: sub['grade']?['feedback']?.toString() ?? '');
    bool saving = false;

    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(builder: (c, setD) {
        final score = num.tryParse(scoreC.text.trim());
        final pct = score != null && maxScore > 0 ? (score / maxScore * 100).round().clamp(0, 999) : null;

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(c).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(c).padding.bottom + 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(
                  width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(color: adaptiveBorder(c), borderRadius: BorderRadius.circular(AppRadii.chip)),
                )),
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Icon(CupertinoIcons.pencil, size: 18, color: Theme.of(c).colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.t('grade_manual_title'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: adaptiveText1(c)))),
                  Tappable(
                    onTap: () => Navigator.pop(c),
                    child: Container(width: 30, height: 30,
                      decoration: BoxDecoration(color: adaptiveSurface2(c), shape: BoxShape.circle),
                      child: const Icon(CupertinoIcons.xmark, color: C.text4, size: 14)),
                  ),
                ]),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: adaptiveSurface2(c), borderRadius: BorderRadius.circular(AppRadii.tile)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.t('grade_score_hint'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.4)),
                    const SizedBox(height: 8),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      SizedBox(
                        width: 90,
                        child: CupertinoTextField(
                          controller: scoreC,
                          keyboardType: TextInputType.number,
                          autofocus: true,
                          placeholder: '0',
                          decoration: null,
                          padding: EdgeInsets.zero,
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Theme.of(c).colorScheme.primary, height: 1),
                          onChanged: (_) => setD(() {}),
                        ),
                      ),
                      Padding(padding: const EdgeInsets.only(bottom: 6, left: 4), child: Text('/ ${maxScore.toInt()}', style: const TextStyle(fontSize: 17, color: C.text4, fontWeight: FontWeight.w600))),
                      const Spacer(),
                      if (pct != null) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: Theme.of(c).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.chip)),
                        child: Text('$pct%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(c).colorScheme.primary)),
                      ),
                    ]),
                  ]),
                ),
                const SizedBox(height: 14),
                Text(l.t('grade_feedback_hint'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text4, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(color: adaptiveSurface2(c), borderRadius: BorderRadius.circular(AppRadii.tile)),
                  child: CupertinoTextField(
                    controller: feedbackC,
                    maxLines: 3,
                    placeholder: l.t('grade_feedback_hint'),
                    decoration: null,
                    padding: const EdgeInsets.all(14),
                    style: TextStyle(fontSize: 15, color: adaptiveText1(c), height: 1.4),
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: saving ? null : () => Navigator.pop(c),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(l.t('cancel')),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: saving || score == null ? null : () async {
                      hapticLight();
                      setD(() => saving = true);
                      try {
                        await context.read<ApiService>().gradeSubmission(
                          (sub['id'] as num).toInt(),
                          score: score,
                          feedback: feedbackC.text.trim().isEmpty ? null : feedbackC.text.trim(),
                        );
                        if (!mounted || !c.mounted) return;
                        final updated = await context.read<ApiService>().getSubmission((sub['id'] as num).toInt());
                        if (!mounted || !c.mounted) return;
                        onGraded(updated);
                        Navigator.pop(c);
                        showToast(context, l.t('grade_saved'));
                      } catch (_) {
                        if (mounted && c.mounted) { setD(() => saving = false); showToast(context, l.t('error'), error: true); }
                      }
                    },
                    child: saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(l.t('grade_save'), style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                  )),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
    // showModalBottomSheet завершает await ещё до начала анимации закрытия
    // (см. TransitionRoute.completed в SDK) — dispose откладываем, иначе ещё
    // видимый TextField ловит "used after being disposed" во время закрытия.
    Future.delayed(const Duration(milliseconds: 400), () {
      scoreC.dispose();
      feedbackC.dispose();
    });
  }

  Future<void> _confirmDeleteSubmission(BuildContext ctx, dynamic sub, VoidCallback onDeleted) async {
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(ctx,
      title: l.t('delete_submission'),
      message: l.t('delete_submission_confirm'),
      icon: CupertinoIcons.trash,
      danger: true,
      confirmText: l.t('delete'),
      cancelText: l.t('cancel'));
    if (ok != true || !mounted || !ctx.mounted) return;
    try {
      await context.read<ApiService>().deleteSubmission((sub['id'] as num).toInt());
      if (!mounted) return;
      showToast(context, l.t('class_deleted'));
      onDeleted();
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    }
  }
}
