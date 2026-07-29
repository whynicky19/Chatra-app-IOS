import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart' show DioException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';
import 'class_detail_utils.dart';
import 'widgets/detail_page_theme.dart';
import 'widgets/file_card.dart';
import '../../utils/dates.dart';

class _UploadFailure implements Exception {
  final String fileName;
  _UploadFailure(this.fileName);
}

String _submitErrorText(L10n l, Object e) {
  if (e is _UploadFailure) return l.t('upload_failed');
  if (e is DioException) {
    final status = e.response?.statusCode;
    final detail = (e.response?.data is Map) ? e.response?.data['detail']?.toString() : null;
    if (status == 409) return l.t('already_submitted');
    if (detail == 'no_active_cohort') return l.t('no_active_cohort');
    if (status == 403) return l.t('archived_submit');
    if (detail != null && detail.isNotEmpty) return detail;
  }
  return l.t('submit_error');
}

/// Полноэкранная страница задания (замена модального bottom sheet).
class AssignmentDetailScreen extends StatefulWidget {
  final dynamic assignment;
  final dynamic submission;
  final bool isTeacher;
  final bool viewOnly;
  final VoidCallback onRefresh;
  final void Function(String url, String name) onOpenFile;
  final void Function(dynamic a) onEditAssignment;
  final void Function(dynamic a) onViewSubmissions;

  const AssignmentDetailScreen({
    super.key,
    required this.assignment,
    required this.submission,
    required this.isTeacher,
    required this.viewOnly,
    required this.onRefresh,
    required this.onOpenFile,
    required this.onEditAssignment,
    required this.onViewSubmissions,
  });

  @override
  State<AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<AssignmentDetailScreen> {
  late Future<Map<String, dynamic>> _assignmentFuture;
  final _tc = TextEditingController();
  bool _busy = false;
  bool _descHidden = false;
  bool _criteriaExpanded = false;
  List<PlatformFile> _pickedFiles = [];

  // Проверка ИИ — единственный блокирующий запрос без стадий на бэкенде,
  // поэтому прогресс симулируем на клиенте (тот же текст, что на Web).
  static const _checkSteps = ['check_step_1', 'check_step_2', 'check_step_3', 'check_step_4', 'check_step_5'];
  int _checkStepIdx = 0;
  Timer? _checkStepTimer;

  dynamic get a => widget.assignment;
  dynamic get sub => widget.submission;

  @override
  void initState() {
    super.initState();
    _assignmentFuture = context.read<ApiService>().getAssignment((a['id'] as num).toInt());
    if (sub != null && sub['status'] == 'grading') {
      _checkStepTimer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
        if (_checkStepIdx < _checkSteps.length - 1) setState(() => _checkStepIdx++);
      });
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    _checkStepTimer?.cancel();
    super.dispose();
  }

  String _fmtDate(String? d) => fmtDate(d);

  List<String> _parseFileUrls(dynamic raw) {
    if (raw == null) return [];
    final api = context.read<ApiService>();
    if (raw is List) {
      return raw.map((f) => api.fixUrl(f.toString())).where((s) => s.isNotEmpty).toList();
    }
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((f) => api.fixUrl(f.toString())).where((s) => s.isNotEmpty).toList();
        }
        if (decoded is String && decoded.isNotEmpty) return [api.fixUrl(decoded)];
      } catch (_) {}
      if (raw.startsWith('http') || raw.startsWith('/')) return [api.fixUrl(raw)];
    }
    return [];
  }

  List<String> _extractFilesFromText(String text) {
    final api = context.read<ApiService>();
    final result = <String>[];
    final seen = <String>{};
    for (final m in mdFileRe.allMatches(text)) {
      var url = m.group(2)!;
      if (!url.contains('#')) url = '$url#${Uri.encodeComponent(m.group(1)!)}';
      url = api.fixUrl(url);
      if (seen.add(url.split('#').first)) result.add(url);
    }
    for (final m in fileUrlRe.allMatches(text.replaceAll(mdFileRe, ''))) {
      final url = api.fixUrl(m.group(0)!);
      if (seen.add(url.split('#').first)) result.add(url);
    }
    return result;
  }

  List<String> _extractReferenceFiles(dynamic listA, [dynamic detailA]) {
    final seen = <String>{};
    final result = <String>[];
    for (final src in [listA, if (detailA != null) detailA]) {
      if (src == null) continue;
      for (final url in [..._parseFileUrls(src['reference_solution_urls']), ..._parseFileUrls(src['reference_solution_url'])]) {
        if (url.isEmpty) continue;
        if (seen.add(_filePathKey(url))) result.add(url);
      }
    }
    return result;
  }

  // Ключ дедупликации — по пути без query: listA (список) и detailA (отдельный
  // getAssignment) — два разных HTTP-ответа, а подписанный URL одного и того же
  // файла в description получает новую подпись/exp в каждом из них.
  String _filePathKey(String url) {
    try { return Uri.parse(url).path; } catch (_) { return url.split('?').first; }
  }

  List<String> _extractAssignmentFiles(dynamic listA, [dynamic detailA]) {
    final seen = <String>{};
    final result = <String>[];
    void addAll(Iterable<String> urls) {
      for (final url in urls) {
        if (url.isEmpty) continue;
        if (seen.add(_filePathKey(url))) result.add(url);
      }
    }
    for (final src in [listA, if (detailA != null) detailA]) {
      if (src == null) continue;
      addAll(_parseFileUrls(src['file_urls']));
      addAll(_parseFileUrls(src['files']));
      addAll(_parseFileUrls(src['attachments']));
      if (src['file_url'] != null) addAll([context.read<ApiService>().fixUrl(src['file_url'].toString())]);
      if (src['description'] != null) {
        addAll(_extractFilesFromText(src['description'].toString()));
      }
    }
    return result;
  }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_tc.text.trim().isEmpty && _pickedFiles.isEmpty) {
      showToast(context, l.t('add_text_or_files'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final api = context.read<ApiService>();
      final fileUrls = <String>[];
      for (final pf in _pickedFiles) {
        if (pf.path == null) continue;
        final res = await api.uploadFile(pf.path!, pf.name);
        final url = res['url'] ?? res['file_url'] ?? res['path'];
        if (url == null) throw _UploadFailure(pf.name);
        fileUrls.add('$url#${Uri.encodeComponent(pf.name)}');
      }
      await api.submitAssignment(a['id'], {
        if (_tc.text.trim().isNotEmpty) 'text_content': _tc.text.trim(),
        if (fileUrls.isNotEmpty) 'file_urls': fileUrls,
      });
      if (mounted) {
        Navigator.pop(context);
        showToast(context, l.t('work_submitted'));
        widget.onRefresh();
      }
    } catch (e) {
      if (mounted) showToast(context, _submitErrorText(l, e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _retract() async {
    final l = context.read<L10n>();
    setState(() => _busy = true);
    try {
      await context.read<ApiService>().retractSubmission(sub['id']);
      if (mounted) {
        Navigator.pop(context);
        showToast(context, l.t('submission_retracted'));
        widget.onRefresh();
      }
    } catch (_) {
      if (mounted) showToast(context, l.t('error_generic'), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _openMenu() {
    final l = context.read<L10n>();
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); widget.onViewSubmissions(a); },
            child: Text(l.t('view_works')),
          ),
          CupertinoActionSheetAction(
            onPressed: () { Navigator.pop(ctx); widget.onEditAssignment(a); },
            child: Text(l.t('edit')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          isDefaultAction: true,
          child: Text(l.t('cancel')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final bg = detailBg(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = detailAccent(context);

    final deadline = a['deadline'];
    final isLate = deadline != null && parseServerDate(deadline)?.isBefore(DateTime.now()) == true && sub == null;
    final statusColor = sub?['status'] == 'graded' ? C.green
        : sub?['status'] == 'needs_review' ? C.amber
        : sub?['status'] == 'submitted' ? accent
        : isLate ? C.red : detailText2(context);
    final statusText = sub?['status'] == 'graded' ? l.t('graded')
        : sub?['status'] == 'needs_review' ? l.t('needs_review')
        : sub?['status'] == 'submitted' ? l.t('submitted')
        : isLate ? l.t('overdue') : l.t('new_status');

    final showSubmitBar = !widget.isTeacher && !widget.viewOnly && sub == null;
    final showRetractBar = !widget.isTeacher && !widget.viewOnly && sub != null && sub['status'] != 'graded' && sub['grade'] == null;
    final showViewWorksBar = widget.isTeacher && !widget.viewOnly;

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: accent,
        scaffoldBackgroundColor: bg,
        barBackgroundColor: bg,
        textTheme: CupertinoTextThemeData(
          primaryColor: accent,
          navLargeTitleTextStyle: TextStyle(
            fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5,
            color: detailText1(context),
          ),
          navTitleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: detailText1(context)),
        ),
      ),
      child: Scaffold(
        backgroundColor: bg,
        body: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            CupertinoSliverNavigationBar(
              backgroundColor: bg,
              border: null,
              stretch: true,
              largeTitle: Text(a['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: widget.isTeacher
                  ? GestureDetector(
                      onTap: _openMenu,
                      child: Icon(CupertinoIcons.ellipsis_circle, size: 26, color: detailText1(context)),
                    )
                  : null,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, showSubmitBar || showRetractBar || showViewWorksBar ? 24 : 48),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                      child: Text(statusText, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: statusColor)),
                    ),
                    const SizedBox(width: 10),
                    Icon(CupertinoIcons.star_fill, size: 13, color: detailText2(context)),
                    const SizedBox(width: 4),
                    Text('${a['max_score'] ?? 100} ${l.t('pts')}', style: TextStyle(fontSize: 14, color: detailText2(context), fontWeight: FontWeight.w500)),
                    if (deadline != null) ...[
                      const SizedBox(width: 10),
                      Container(width: 3, height: 3, decoration: BoxDecoration(color: detailText2(context), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Icon(CupertinoIcons.calendar, size: 13, color: isLate ? C.red : detailText2(context)),
                      const SizedBox(width: 4),
                      Text(_fmtDate(deadline), style: TextStyle(fontSize: 14, color: isLate ? C.red : detailText2(context), fontWeight: FontWeight.w500)),
                    ],
                  ]),
                  const SizedBox(height: 26),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _assignmentFuture,
                    builder: (ctx, snap) {
                      final detailA = snap.data;
                      final isLoading = snap.connectionState == ConnectionState.waiting;
                      final descText = cleanContent(((detailA?['description'] ?? a['description'])?.toString()) ?? '');
                      final allFiles = _extractAssignmentFiles(a, detailA);

                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (descText.isNotEmpty) ...[
                          Row(children: [
                            Expanded(child: Text(l.t('description'),
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context)))),
                            GestureDetector(
                              onTap: () => setState(() => _descHidden = !_descHidden),
                              child: Text(_descHidden ? l.t('show') : l.t('hide'),
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
                            ),
                          ]),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeInOut,
                            child: _descHidden
                                ? const SizedBox(height: 8)
                                : Padding(
                                    padding: const EdgeInsets.only(top: 10, bottom: 8),
                                    child: Text(descText,
                                        style: TextStyle(fontSize: 16.5, height: 1.65, letterSpacing: 0.1, color: detailText1(context))),
                                  ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (isLoading)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                              const SizedBox(width: 10),
                              Text(l.t('loading_files'), style: TextStyle(fontSize: 13, color: detailText2(context))),
                            ]),
                          )
                        else if (allFiles.isNotEmpty) ...[
                          Text(l.t('attached_files_edit'),
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context))),
                          const SizedBox(height: 12),
                          for (final f in allFiles) ...[
                            FileCard(name: fileDisplayName(f), onTap: () => widget.onOpenFile(f, fileDisplayName(f))),
                            const SizedBox(height: 10),
                          ],
                          const SizedBox(height: 12),
                        ],
                        if (descText.isEmpty && !isLoading && allFiles.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(l.t('content_empty'), style: TextStyle(fontSize: 14, color: detailText2(context), fontWeight: FontWeight.w500)),
                          ),
                      ]);
                    },
                  ),
                  if (widget.isTeacher) ...(() {
                    final refFiles = _extractReferenceFiles(a);
                    if (refFiles.isEmpty) return <Widget>[];
                    return [
                      Text(l.t('reference_files'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context))),
                      const SizedBox(height: 12),
                      for (final f in refFiles) ...[
                        FileCard(name: fileDisplayName(f), onTap: () => widget.onOpenFile(f, fileDisplayName(f))),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 12),
                    ];
                  })(),
                  if (widget.isTeacher) ...(() {
                    List<dynamic> criteria = [];
                    try { criteria = jsonDecode(a['criteria'] ?? '[]'); } catch (_) {}
                    if (criteria.isEmpty) return <Widget>[];
                    return [
                      GestureDetector(
                        onTap: () => setState(() => _criteriaExpanded = !_criteriaExpanded),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: detailBorder(context))),
                          child: Row(children: [
                            Icon(CupertinoIcons.list_bullet, size: 16, color: accent),
                            const SizedBox(width: 8),
                            Text(l.t('criteria'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: detailText1(context))),
                            const SizedBox(width: 4),
                            Text('(${criteria.length})', style: TextStyle(fontSize: 12, color: detailText2(context))),
                            const Spacer(),
                            AnimatedRotation(turns: _criteriaExpanded ? 0.5 : 0.0, duration: const Duration(milliseconds: 200),
                                child: Icon(CupertinoIcons.chevron_down, size: 18, color: accent)),
                          ]),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
                        child: _criteriaExpanded
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(children: criteria.map<Widget>((c) => Container(
                                  margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(14)),
                                  child: Row(children: [
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(c['name'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: detailText1(context))),
                                      if (c['description'] != null && c['description'].toString().isNotEmpty)
                                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(c['description'], style: TextStyle(fontSize: 12.5, color: detailText2(context)))),
                                    ])),
                                    Text('${c['weight'] ?? 0}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
                                  ]),
                                )).toList()),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 20),
                    ];
                  })(),
                  if (sub?['grade'] != null) ...[
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(20), border: Border.all(color: detailBorder(context))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          RichText(text: TextSpan(children: [
                            TextSpan(text: '${sub['grade']['score']}', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: accent, height: 1)),
                            TextSpan(text: ' / ${a['max_score']}', style: TextStyle(fontSize: 17, color: detailText2(context), fontWeight: FontWeight.w600)),
                          ])),
                          const Spacer(),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(sub['grade']['graded_by'] == 'ai' ? CupertinoIcons.bolt_fill : CupertinoIcons.person, size: 13, color: accent),
                              const SizedBox(width: 4),
                              Text(sub['grade']['graded_by'] == 'ai' ? l.t('ai_check') : l.t('teacher_short'), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
                            ])),
                        ]),
                        if (widget.isTeacher && sub['ai_confidence'] != null) ...[
                          const SizedBox(height: 8),
                          Text('${l.t('confidence_label')}: ${sub['ai_confidence']}%', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: detailText2(context))),
                        ],
                        if (sub['grade']['feedback'] != null) ...[
                          const SizedBox(height: 14),
                          Text(sub['grade']['feedback'], style: TextStyle(fontSize: 15, color: detailText1(context), height: 1.6)),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 20),
                    ...(() {
                      final criteria = parseCriteriaScores(sub['grade']['criteria_scores']);
                      if (criteria.isEmpty) return <Widget>[];
                      return [
                        Text(l.t('by_criteria'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context))),
                        const SizedBox(height: 12),
                        for (final c in criteria) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(c['name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: detailText1(context)))),
                                RichText(text: TextSpan(children: [
                                  TextSpan(text: '${c['score'] ?? 0}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accent)),
                                  TextSpan(text: ' / ${c['max'] ?? 0}', style: TextStyle(fontSize: 13, color: detailText2(context))),
                                ])),
                              ]),
                              if ((c['comment'] ?? '').toString().isNotEmpty)
                                Padding(padding: const EdgeInsets.only(top: 6), child: Text(c['comment'], style: TextStyle(fontSize: 13, color: detailText2(context), height: 1.5))),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 12),
                      ];
                    })(),
                  ],
                  if (sub != null && sub['status'] == 'grading' && sub['grade'] == null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: 0.2))),
                      child: Row(children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(l.t(_checkSteps[_checkStepIdx]), style: TextStyle(fontSize: 13.5, color: accent, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (sub != null && sub['status'] == 'needs_review') ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: C.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.amber.withValues(alpha: 0.3))),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(CupertinoIcons.exclamationmark_circle, size: 16, color: C.amber),
                        const SizedBox(width: 10),
                        Expanded(child: Text(l.t('needs_review_student_msg'), style: TextStyle(fontSize: 13.5, height: 1.5, color: detailText2(context)))),
                      ]),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (sub != null && (sub['text_content'] != null || sub['file_urls'] != null)) ...[
                    Text(l.t('your_answer'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context))),
                    const SizedBox(height: 12),
                    if (sub['text_content'] != null && sub['text_content'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(sub['text_content'], style: TextStyle(fontSize: 15.5, height: 1.6, color: detailText1(context))),
                      ),
                    ...(() {
                      final urls = _parseFileUrls(sub['file_urls']);
                      return [
                        for (final url in urls) ...[
                          FileCard(name: fileDisplayName(url), onTap: () => widget.onOpenFile(url, fileDisplayName(url))),
                          const SizedBox(height: 10),
                        ],
                      ];
                    })(),
                    const SizedBox(height: 8),
                  ],
                  if (!widget.isTeacher && widget.viewOnly && sub == null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        Icon(CupertinoIcons.lock, size: 15, color: detailText2(context)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(l.t('archive_readonly'), style: TextStyle(fontSize: 12.5, color: detailText2(context), fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  if (showSubmitBar) ...[
                    const SizedBox(height: 4),
                    Text(l.t('submit_work'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: detailText1(context))),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: detailBorder(context))),
                      child: CupertinoTextField(
                        controller: _tc,
                        maxLines: 4,
                        placeholder: l.t('work_text_hint'),
                        placeholderStyle: TextStyle(color: detailText2(context), fontSize: 15),
                        style: TextStyle(fontSize: 15, color: detailText1(context)),
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.any);
                        if (result != null) setState(() => _pickedFiles = result.files);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(16), border: Border.all(color: detailBorder(context))),
                        child: Row(children: [
                          Icon(CupertinoIcons.paperclip, color: accent, size: 19),
                          const SizedBox(width: 10),
                          Expanded(child: Text(
                            _pickedFiles.isEmpty ? l.t('attach_file') : '${l.t('files_selected')}: ${_pickedFiles.length}',
                            style: TextStyle(fontSize: 14.5, color: _pickedFiles.isEmpty ? detailText2(context) : accent, fontWeight: _pickedFiles.isEmpty ? FontWeight.normal : FontWeight.w600),
                          )),
                          Icon(CupertinoIcons.chevron_right, color: detailText2(context), size: 17),
                        ]),
                      ),
                    ),
                    if (_pickedFiles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ..._pickedFiles.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(children: [
                          Icon(CupertinoIcons.doc, size: 14, color: accent),
                          const SizedBox(width: 6),
                          Expanded(child: Text(f.name, style: TextStyle(fontSize: 12.5, color: detailText2(context)), overflow: TextOverflow.ellipsis)),
                          GestureDetector(onTap: () => setState(() => _pickedFiles.removeWhere((x) => x.name == f.name)),
                            child: Icon(CupertinoIcons.xmark, size: 14, color: detailText2(context))),
                        ]),
                      )),
                    ],
                  ],
                ]),
              ),
            ),
          ],
        ),
        bottomNavigationBar: showSubmitBar
            ? _BottomActionBar(
                label: l.t('submit_assignment'),
                busy: _busy,
                accent: accent,
                onTap: _submit,
              )
            : showRetractBar
                ? _BottomActionBar(
                    label: l.t('retract_resubmit'),
                    busy: _busy,
                    accent: accent,
                    secondary: true,
                    onTap: _retract,
                  )
                : showViewWorksBar
                    ? _BottomActionBar(
                        label: l.t('view_works'),
                        busy: false,
                        accent: accent,
                        onTap: () => widget.onViewSubmissions(a),
                      )
                    : null,
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final String label;
  final bool busy;
  final Color accent;
  final bool secondary;
  final VoidCallback onTap;
  const _BottomActionBar({required this.label, required this.busy, required this.accent, required this.onTap, this.secondary = false});

  @override
  Widget build(BuildContext context) {
    final bg = detailBg(context);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: detailBorder(context))),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(16),
            color: secondary ? detailSurface(context) : accent,
            onPressed: busy ? null : onTap,
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CupertinoActivityIndicator(color: Colors.white))
                : Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: secondary ? detailText1(context) : Colors.white)),
          ),
        ),
      ),
    );
  }
}
