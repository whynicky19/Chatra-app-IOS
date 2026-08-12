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
import '../../../widgets/inset_group.dart';
import '../../../widgets/tappable.dart';
import '../../../widgets/toast.dart';
import '../class_detail_utils.dart';
import '../assignment_detail_screen.dart';
import '../widgets/detail_page_theme.dart';
import '../widgets/file_card.dart';
import '../widgets/score_ring.dart';
import '../../../utils/dates.dart';
import '../../../utils/haptics.dart';
import '../../../utils/nav_guard.dart';

class ClassAssignmentsTab extends StatefulWidget {
  final List<dynamic> assignments;
  final List<dynamic> mySubs;
  final Map<String, dynamic> rating;
  final bool isTeacher;
  final int classId;
  final bool isLoading;
  final bool viewOnly;
  final int? cohortId;
  final Future<void> Function() onRefresh;
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

  String _fileDisplayName(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.fragment.isNotEmpty) return Uri.decodeComponent(uri.fragment);
      return uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => url);
    } catch (_) { return url; }
  }

  Widget _statCell(String val, String label, Color color) => Expanded(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
    child: Column(children: [
      Text(val, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.8, color: color, fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: adaptiveText4(context), letterSpacing: -0.1)),
    ])));

  Widget _statDivider(BuildContext context) => Container(
    width: hairline(context),
    margin: const EdgeInsets.symmetric(vertical: 12),
    color: groupSeparator(context),
  );

  // Та же карточка результата, что видит студент на AssignmentDetailScreen —
  // кольцо с баллом + критерии-полосы вместо старой плоской вёрстки, чтобы
  // учитель/админ видели идентичный дизайн после проверки работы.
  Widget _gradedScoreCard(BuildContext context, L10n l, dynamic grade, num score, String? feedback, List<dynamic> criteria, num maxScore) {
    final accent = detailAccent(context);
    final gradedByTeacher = grade != null && grade['graded_by'] == 'teacher';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: detailSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: detailBorder(context), width: hairline(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(l.t('preliminary_assessment'), style: cardTitleStyle(context))),
          if (!gradedByTeacher)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(CupertinoIcons.sparkles, size: 11, color: accent),
                const SizedBox(width: 4),
                Text(l.t('ai_check'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: -0.1)),
              ]),
            ),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ScoreRing(score: score, maxScore: maxScore, size: 108, accentColor: accent),
          if (feedback != null && feedback.isNotEmpty) ...[
            const SizedBox(width: 16),
            Expanded(child: Text(feedback,
                style: TextStyle(fontSize: 15, height: 1.45, letterSpacing: -0.2, color: detailText2(context)))),
          ],
        ]),
        if (criteria.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(l.t('by_criteria').toUpperCase(), style: sectionCaptionStyle(context)),
          const SizedBox(height: 14),
          for (var i = 0; i < criteria.length; i++) ...[
            _criteriaBar(context, criteria[i]),
            if (i != criteria.length - 1) const SizedBox(height: 16),
          ],
        ],
      ]),
    );
  }

  /// Пара «метка — значение» в блоке спорной работы: значение выровнено по
  /// правому краю табличными цифрами, чтобы несколько строк читались столбцом.
  Widget _reviewStat(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText3(context)))),
      const SizedBox(width: 10),
      Text(value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2,
              color: adaptiveText1(context), fontFeatures: const [FontFeature.tabularFigures()])),
    ]),
  );

  Widget _criteriaBar(BuildContext context, dynamic c) {
    final score = (c['score'] as num?) ?? 0;
    final max = (c['max'] as num?) ?? (c['max_score'] as num?) ?? (c['weight'] as num?) ?? 0;
    final ratio = max > 0 ? (score.toDouble() / max.toDouble()).clamp(0.0, 1.0) : 0.0;
    final accent = detailAccent(context);
    final comment = (c['comment'] ?? c['feedback'])?.toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['name']?.toString() ?? '',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context))),
          if (comment != null && comment.isNotEmpty)
            Text(comment, style: TextStyle(fontSize: 13, height: 1.3, color: detailText2(context))),
        ])),
        const SizedBox(width: 8),
        RichText(text: TextSpan(children: [
          TextSpan(text: '$score',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: accent, letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()])),
          TextSpan(text: ' / $max',
              style: TextStyle(fontSize: 13, color: detailText2(context), fontFeatures: const [FontFeature.tabularFigures()])),
        ])),
      ]),
      const SizedBox(height: 9),
      SizedBox(
        width: double.infinity,
        height: 7,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: Stack(children: [
            Positioned.fill(child: Container(color: detailBorder(context))),
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: ratio),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, value, __) => FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: value, child: Container(color: accent)),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    if (widget.isLoading) return Center(child: CupertinoActivityIndicator(radius: 13, color: Theme.of(context).colorScheme.primary));
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
    // Тёмная ступень градиента берётся из палитры темы, а не хардкодом
    // (#006475 — teal): в школьной теме (amber) синий градиент выпадал из
    // всего остального оформления экрана.
    final primary = Theme.of(context).colorScheme.primary;
    final primaryDeep = primary == C.amber ? C.amberDeep : C.tealDeep;

    final headers = <Widget>[
      if (!widget.isTeacher && widget.rating.isNotEmpty) Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primaryDeep, primary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.t('your_rating').toUpperCase(),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.7)),
              const SizedBox(height: 10),
              // tabularFigures: цифры одинаковой ширины — иначе балл «дышит»
              // по ширине при каждом обновлении рейтинга.
              RichText(text: TextSpan(children: [
                TextSpan(text: '$avg', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w700, height: 1, letterSpacing: -1.2, fontFeatures: [FontFeature.tabularFigures()])),
                const TextSpan(text: ' /100', style: TextStyle(color: Colors.white60, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
              ])),
              const Spacer(),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(
                value: avg / 100, backgroundColor: Colors.white24, color: Colors.white, minHeight: 5)),
              const SizedBox(height: 7),
              Text('${l.t('performance')}: $pct%', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: -0.1)),
            ]),
          )),
          const SizedBox(width: 12),
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
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.card)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('next_deadline').toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: adaptiveText4(context), letterSpacing: 0.7)),
                const Spacer(),
                const Center(child: Icon(CupertinoIcons.checkmark_circle_fill, size: 30, color: C.green)),
                const SizedBox(height: 8),
                Center(child: Text(l.t('all_submitted'), textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: C.green, fontWeight: FontWeight.w600, letterSpacing: -0.1))),
                const Spacer(),
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
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(AppRadii.card)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.t('next_deadline').toUpperCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: adaptiveText4(context), letterSpacing: 0.7)),
                const SizedBox(height: 12),
                Row(children: [
                  Container(
                    width: 46, height: 52,
                    decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(months[dl.month - 1].toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: primary, letterSpacing: 0.5)),
                      Text('${dl.day}',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: primary, height: 1.1, letterSpacing: -0.6, fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Две строки: названия вида «Лабораторная работа 5» в одну
                    // строку не помещаются и обрезаются до «Лаборатор…».
                    Text(next['title'] ?? '',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.2, color: adaptiveText1(context)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Row(children: [
                      Icon(CupertinoIcons.clock, size: 11, color: days <= 1 ? C.red : primary),
                      const SizedBox(width: 3),
                      Expanded(child: Text(remaining,
                          style: TextStyle(fontSize: 13, color: days <= 1 ? C.red : primary, fontWeight: FontWeight.w600, letterSpacing: -0.1),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ])),
                ]),
              ]),
            );
          })),
        ])),
      ),
      if (widget.assignments.isNotEmpty)
        SectionTitle(title: l.t('assignments'), padding: const EdgeInsets.fromLTRB(2, 0, 2, 12)),
      if (widget.assignments.isEmpty) Container(padding: const EdgeInsets.fromLTRB(28, 44, 28, 60), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 76, height: 76,
          decoration: BoxDecoration(gradient: RadialGradient(colors: [primary.withValues(alpha: 0.16), primary.withValues(alpha: 0.03)]), shape: BoxShape.circle),
          child: Icon(CupertinoIcons.doc_text, size: 32, color: primary)),
        const SizedBox(height: 18),
        Text(l.t('no_assignments'), textAlign: TextAlign.center,
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: adaptiveText1(context))),
        const SizedBox(height: 6),
        Text(widget.isTeacher ? l.t('create_first_assignment') : l.t('no_assignments_yet'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, height: 1.4, color: adaptiveText3(context))),
      ]))),
    ];
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
        SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          childCount: headers.length + widget.assignments.length,
          (ctx, index) {
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

        final showBadge = isGraded || isNeedsReview || isSubmitted || isLate;
        final Color statusColor = isGraded ? C.green : isNeedsReview ? C.amber : isSubmitted ? primary : C.red;
        final String statusText = isGraded ? l.t('graded') : isNeedsReview ? l.t('needs_review') : isSubmitted ? l.t('submitted') : l.t('overdue');
        final IconData statusIcon = isGraded ? CupertinoIcons.checkmark_circle_fill : isNeedsReview ? CupertinoIcons.exclamationmark_triangle : isSubmitted ? CupertinoIcons.arrow_up_doc : CupertinoIcons.clock;
        // Значок показывает состояние САМОЙ РАБОТЫ (проверена / сдана / нужна
        // ручная проверка). Просроченный дедлайн его не красит: работа ещё не
        // сдана, состояние прежнее, а красная плитка в списке читалась как
        // ошибка. Сам факт просрочки остаётся в мете красным текстом.
        final hasSubmissionStatus = isGraded || isNeedsReview || isSubmitted;
        final Color leadColor = hasSubmissionStatus ? statusColor : adaptiveText4(context);
        final IconData leadIcon = hasSubmissionStatus ? statusIcon : CupertinoIcons.doc_text;

        return Entrance(
          key: ValueKey('asgn_${a['id']}'),
          index: i,
          child: RepaintBoundary(child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            // Отдельная карточка на задание — см. class_posts_tab.
            // Ровно две строки текста, как в карточке лекции: название и мета
            // (срок · статус). Превью описания убрано — оно давало разную
            // высоту карточкам и четвёртый блок, спорящий за внимание.
            child: GroupRow.card(
            onTap: () => _showAssignment(a, sub),
            onLongPress: widget.isTeacher ? () => _showAssignmentActions(a) : null,
            // Те же метрики, что у карточки лекции (см. class_posts_tab):
            // плитка 46, body 17 / subheadline 15, воздух 16 по вертикали.
            padding: EdgeInsets.fromLTRB(16, 16, widget.isTeacher ? 6 : 16, 16),
            child: Row(children: [
              Container(
                width: 46, height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: leadColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
                child: Icon(leadIcon, size: 21, color: leadColor),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] ?? '',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.25, letterSpacing: -0.4, color: adaptiveText1(context)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                // Срок и статус одной приглушённой строкой, без иконки-
                // календарика: цвет несёт только статус, и то текстом.
                Row(children: [
                  // Строка меты никогда не бывает пустой: у задания без срока и
                  // без статуса показываем максимальный балл. Пустой Row имел
                  // нулевую высоту, и такая карточка оказывалась на пиксель
                  // ниже соседних — ровно тот разнобой, который мы убираем.
                  if (deadline == null && !showBadge)
                    Text('${a['max_score'] ?? 100} ${l.t('pts')}',
                        style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
                  if (deadline != null)
                    Text(_fmtDate(deadline),
                        style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: adaptiveText4(context))),
                  if (deadline != null && showBadge)
                    Text('  ·  ', style: TextStyle(fontSize: 15, color: adaptiveText4(context))),
                  if (showBadge)
                    Flexible(child: Text(statusText,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: statusColor, letterSpacing: -0.2),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ])),
              if (grade != null) ...[
                const SizedBox(width: 10),
                RichText(text: TextSpan(children: [
                  TextSpan(text: '${grade['score']}',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: C.green, letterSpacing: -0.5, fontFeatures: [FontFeature.tabularFigures()])),
                  TextSpan(text: '/${a['max_score']}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: adaptiveText4(context))),
                ])),
              ],
              // Вертикальное троеточие — как в системных списках iOS. Шеврона
              // «открыть» нет: нажимается вся карточка, а стрелка была
              // третьим значком в строке и только добавляла шума.
              if (widget.isTeacher)
                Tappable(
                  onTap: () => _showAssignmentActions(a),
                  label: 'Действия с заданием',
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
      ],
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
    guardedPush(context, MaterialPageRoute(builder: (_) => AssignmentDetailScreen(
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
              // Отдельный от build() флаг темы: этот лист живёт в своём
              // builder-контексте модального окна.
              final isDark = Theme.of(ctx).brightness == Brightness.dark;
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
                // Возврат — текстовая кнопка с шевроном (как «< Назад» в iOS),
                // а не серая плашка-чип.
                Align(
                  alignment: Alignment.centerLeft,
                  child: Tappable(
                    onTap: () => setS(() => selectedSub = null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(CupertinoIcons.chevron_left, size: 17, color: Theme.of(ctx).colorScheme.primary),
                        const SizedBox(width: 3),
                        Text(l.t('back_to_list'),
                            style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: Theme.of(ctx).colorScheme.primary)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  CircleAvatar(radius: 24, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      child: Text(initials, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.3))),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: adaptiveText1(context)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(selectedSub['submitted_at'] != null ? _fmtDate(selectedSub['submitted_at']) : '',
                        style: TextStyle(fontSize: 14, color: adaptiveText4(context))),
                  ])),
                ]),
                if (selectedSub['text_content'] != null || submittedFileUrls.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text(l.t('student_work').toUpperCase(), style: sectionCaptionStyle(context)),
                  ),
                  if (selectedSub['text_content'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: sectionCard(context, isDark, children: [
                        Text(selectedSub['text_content'],
                            style: TextStyle(fontSize: 16, height: 1.55, letterSpacing: -0.2, color: detailText1(context))),
                      ]),
                    ),
                  // Тот же сгруппированный список вложений, что на странице
                  // задания у студента: раньше здесь были свои акцентно-синие
                  // плашки со своей иконографией.
                  if (submittedFileUrls.isNotEmpty)
                    FileList(
                      files: [
                        for (final url in submittedFileUrls)
                          FileEntry(name: _fileDisplayName(url), url: url, previewUrl: url),
                      ],
                      onOpen: (f) => widget.onOpenFile(f.url, f.name),
                    ),
                ],
                if (selectedSub['status'] == 'needs_review') ...[
                  const SizedBox(height: 20),
                  // Разбор ИИ по спорной работе: заголовок-предупреждение,
                  // затем сами цифры парами «метка — значение» и критерии
                  // одним сгруппированным списком (было: карточка в карточке,
                  // где каждый критерий получал свою рамку).
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: C.amber.withValues(alpha: isDark ? 0.12 : 0.09),
                      borderRadius: BorderRadius.circular(AppRadii.card),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(CupertinoIcons.exclamationmark_triangle_fill, size: 16, color: C.amber),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l.t('status_needs_review_label'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: C.amber))),
                      ]),
                      if (score != null)
                        _reviewStat(context, l.t('suggested_score_label'), '$score / $assignmentMaxScore'),
                      if (selectedSub['ai_confidence'] != null)
                        _reviewStat(context, l.t('confidence_label'), '${selectedSub['ai_confidence']}%'),
                      if (_parseStringList(selectedSub['ai_review_reasons']).isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(l.t('review_reasons_label').toUpperCase(), style: sectionCaptionStyle(context)),
                        const SizedBox(height: 6),
                        for (final r in _parseStringList(selectedSub['ai_review_reasons']))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 5),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 8, right: 9),
                                  decoration: const BoxDecoration(color: C.amber, shape: BoxShape.circle)),
                              Expanded(child: Text(r,
                                  style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.2, color: detailText1(context)))),
                            ]),
                          ),
                      ],
                      if (feedback != null || criteria.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(l.t('ai_analysis_label').toUpperCase(), style: sectionCaptionStyle(context)),
                        if (feedback != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(feedback,
                                style: TextStyle(fontSize: 15, height: 1.45, letterSpacing: -0.2, color: detailText1(context))),
                          ),
                        if (criteria.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          InsetGroup(children: [
                            for (var i = 0; i < criteria.length; i++)
                              GroupRow(
                                pos: innerPos(i, criteria.length),
                                color: Colors.transparent,
                                separatorInset: 14,
                                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(criteria[i]['name'] ?? '',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: adaptiveText1(context)))),
                                    const SizedBox(width: 8),
                                    Text('${criteria[i]['score'] ?? 0} / ${criteria[i]['max'] ?? criteria[i]['max_score'] ?? criteria[i]['weight'] ?? 0}',
                                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.3,
                                            color: Theme.of(ctx).colorScheme.primary, fontFeatures: const [FontFeature.tabularFigures()])),
                                  ]),
                                  if ((criteria[i]['comment'] ?? criteria[i]['feedback']) != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(criteria[i]['comment'] ?? criteria[i]['feedback'],
                                          style: TextStyle(fontSize: 14, color: adaptiveText3(context), height: 1.35)),
                                    ),
                                ]),
                              ),
                          ]),
                        ],
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
                  _gradedScoreCard(context, l, grade, score, feedback?.toString(), criteria, assignmentMaxScore),
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
              Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: adaptiveText4(context).withValues(alpha: 0.35), borderRadius: BorderRadius.circular(100)))),
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 14),
                child: Text(l.t('view_works'),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: adaptiveText1(context))),
              ),
              // Сводка одной карточкой с вертикальными волосяными
              // разделителями (как итоги в Apple Health), а не три отдельные
              // плитки с рамками, спорящие за внимание.
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.card),
                  border: Border.all(color: groupSeparator(context), width: hairline(context)),
                ),
                child: IntrinsicHeight(child: Row(children: [
                  _statCell('${subs.length}', l.t('total'), adaptiveText1(context)),
                  _statDivider(context),
                  _statCell('$graded', l.t('checked'), Theme.of(context).colorScheme.primary),
                  _statDivider(context),
                  _statCell('$pending', l.t('pending'), pending > 0 ? C.amberDk : adaptiveText4(context)),
                ])),
              ),
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
              // Нативное поле поиска iOS вместо обычного TextField с иконкой:
              // приходит вместе с кнопкой очистки и правильными метриками.
              CupertinoSearchTextField(
                placeholder: l.t('search_student'),
                backgroundColor: adaptiveSurface2(context),
                style: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveText1(context)),
                placeholderStyle: TextStyle(fontSize: 16, letterSpacing: -0.3, color: adaptiveText4(context)),
                itemColor: adaptiveText4(context),
                onChanged: (v) => setS(() => search = v),
              ),
              const SizedBox(height: 14),
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
                final primaryColor = Theme.of(context).colorScheme.primary;
                return GroupRow(
                  pos: groupPos(index - gradeHeaders.length, filtered.length),
                  onTap: () => setS(() => selectedSub = s),
                  separatorInset: 64,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(children: [
                    CircleAvatar(radius: 19, backgroundColor: primaryColor.withValues(alpha: 0.15),
                        child: Text(initials, style: TextStyle(color: primaryColor, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: adaptiveText1(context)),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(s['submitted_at'] != null ? _fmtDate(s['submitted_at']) : '',
                          style: TextStyle(fontSize: 13, color: adaptiveText4(context))),
                    ])),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (score != null)
                        Text('$score/100',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: primaryColor, fontFeatures: const [FontFeature.tabularFigures()]))
                      else
                        Text('—', style: TextStyle(fontSize: 17, color: adaptiveText4(context))),
                      Text(isGraded ? l.t('graded_one') : isNeedsReview ? l.t('needs_review') : l.t('pending_one'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: -0.1,
                              color: isGraded ? primaryColor : isNeedsReview ? C.amber : C.amberDk)),
                    ]),
                  ]),
                );
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
