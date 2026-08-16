import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart' show DioException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_button.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'class_detail_utils.dart';
import 'widgets/detail_page_theme.dart';
import 'widgets/file_card.dart';
import 'widgets/score_ring.dart';
import '../../utils/dates.dart';
import '../../utils/upload_limits.dart';

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

String _fmtBytes(int bytes) => bytes < 1048576 ? '${(bytes / 1024).toStringAsFixed(0)} KB' : '${(bytes / 1048576).toStringAsFixed(1)} MB';

const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

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
  bool _rubricExpanded = false;
  List<PlatformFile> _pickedFiles = [];
  final Set<String> _uploadedNames = {};
  String? _uploadingName;

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
    setState(() { _busy = true; _uploadedNames.clear(); _uploadingName = null; });
    try {
      final api = context.read<ApiService>();
      final fileUrls = <String>[];
      for (final pf in _pickedFiles) {
        final path = pf.path;
        if (path == null) continue;
        if (mounted) setState(() => _uploadingName = pf.name);
        final res = await api.uploadFile(path, pf.name);
        final url = res['url'] ?? res['file_url'] ?? res['path'];
        if (url == null) throw _UploadFailure(pf.name);
        fileUrls.add('${encodeUploadedFileUrl(url.toString())}#${Uri.encodeComponent(pf.name)}');
        if (mounted) setState(() { _uploadedNames.add(pf.name); _uploadingName = null; });
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

  List<Map<String, dynamic>> _rubricCriteria() {
    try {
      final decoded = jsonDecode(a['criteria']?.toString() ?? '[]');
      if (decoded is List) return decoded.cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    } catch (_) {}
    return [];
  }

  String? _rubricDescriptionFor(String name, List<Map<String, dynamic>> rubric) {
    for (final c in rubric) {
      if ((c['name']?.toString() ?? '') == name) {
        final d = c['description']?.toString();
        return (d != null && d.isNotEmpty) ? d : null;
      }
    }
    return null;
  }

  (List<String>, List<String>) _splitStrengthsWeaknesses(List<Map<String, dynamic>> criteria) {
    final strengths = <String>[];
    final weaknesses = <String>[];
    for (final c in criteria) {
      final score = (c['score'] as num?)?.toDouble() ?? 0;
      final max = (c['max'] as num?)?.toDouble() ?? 0;
      final ratio = max > 0 ? score / max : 0.0;
      final comment = (c['comment']?.toString() ?? '').trim();
      final name = (c['name']?.toString() ?? '').trim();
      final text = comment.isNotEmpty ? comment : name;
      if (text.isEmpty) continue;
      if (ratio >= 0.7) {
        strengths.add(text);
      } else {
        weaknesses.add(text);
      }
    }
    return (strengths, weaknesses);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<L10n>();
    final bg = detailBg(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final deadline = a['deadline'];
    final isLate = deadline != null && parseServerDate(deadline)?.isBefore(DateTime.now()) == true && sub == null;

    final showSubmitBar = !widget.isTeacher && !widget.viewOnly && sub == null;
    final showRetractBar = !widget.isTeacher && !widget.viewOnly && sub != null && sub['status'] != 'graded' && sub['grade'] == null;
    final showViewWorksBar = widget.isTeacher && !widget.viewOnly;

    final grade = sub?['grade'];
    final gradedByTeacher = grade != null && sub['grade']['graded_by'] == 'teacher';
    final gradedByAi = grade != null && !gradedByTeacher;
    final criteriaScores = grade != null
        ? parseCriteriaScores(sub['grade']['criteria_scores']).cast<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : <Map<String, dynamic>>[];
    final rubric = _rubricCriteria();
    final accent = detailAccent(context);

    return CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: accent,
        scaffoldBackgroundColor: bg,
        barBackgroundColor: bg,
      ),
      child: Scaffold(
        backgroundColor: bg,
        // extendBody: контент проезжает ПОД нижней панелью действий — только
        // тогда её матовое стекло имеет смысл (иначе размывать нечего).
        extendBody: true,
        body: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, 8, 20,
                showSubmitBar || showRetractBar || showViewWorksBar ? 104 : 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              _topBar(context, isDark),
              const SizedBox(height: 16),
              _titleBlock(context, l, grade),
              const SizedBox(height: 12),
              _statusChips(context, l, isLate),
              const SizedBox(height: 12),
              _dueReviewedRow(context, l, deadline, isLate, grade),
              const SizedBox(height: 24),

              if (grade == null && sub != null && sub['status'] == 'grading') ...[
                _pendingBanner(context, accent, icon: CupertinoIcons.hourglass,
                    text: l.t(_checkSteps[_checkStepIdx]), showSpinner: true),
                const SizedBox(height: 16),
              ] else if (grade == null && sub != null && sub['status'] == 'needs_review') ...[
                _pendingBanner(context, C.amber, icon: CupertinoIcons.exclamationmark_circle,
                    text: l.t('needs_review_student_msg')),
                const SizedBox(height: 16),
              ],

              // ── Задание: описание + файлы, единой карточкой ──
              FutureBuilder<Map<String, dynamic>>(
                future: _assignmentFuture,
                builder: (ctx, snap) {
                  final detailA = snap.data;
                  final isLoading = snap.connectionState == ConnectionState.waiting;
                  final descText = cleanContent(((detailA?['description'] ?? a['description'])?.toString()) ?? '');
                  final allFiles = _extractAssignmentFiles(a, detailA);
                  if (descText.isEmpty && !isLoading && allFiles.isEmpty) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (descText.isNotEmpty || isLoading)
                        sectionCard(context, isDark, children: [
                          Row(children: [
                            Expanded(child: Text(l.t('description'), style: cardTitleStyle(context))),
                            if (descText.isNotEmpty)
                              Tappable(
                                onTap: () => setState(() => _descHidden = !_descHidden),
                                child: Text(_descHidden ? l.t('show') : l.t('hide'),
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: accent)),
                              ),
                          ]),
                          if (descText.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeInOut,
                              alignment: Alignment.topCenter,
                              child: _descHidden
                                  ? const SizedBox.shrink()
                                  : Text(descText,
                                      style: TextStyle(fontSize: 16, height: 1.55, letterSpacing: -0.2, color: detailText2(context))),
                            ),
                          ],
                          if (isLoading) ...[
                            SizedBox(height: descText.isNotEmpty ? 14 : 12),
                            Row(children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                              const SizedBox(width: 10),
                              Text(l.t('loading_files'), style: TextStyle(fontSize: 14, color: detailText2(context))),
                            ]),
                          ],
                        ]),
                      if (!isLoading && allFiles.isNotEmpty) ...[
                        SizedBox(height: descText.isNotEmpty ? 20 : 0),
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(l.t('task_files').toUpperCase(), style: sectionCaptionStyle(context)),
                        ),
                        FileList(
                          files: [for (final f in allFiles) FileEntry(name: fileDisplayName(f), url: f, previewUrl: f)],
                          onOpen: (f) => widget.onOpenFile(f.url, f.name),
                        ),
                      ],
                    ]),
                  );
                },
              ),

              // ── Эталонное решение (только учитель) ──
              if (widget.isTeacher) ...(() {
                final refFiles = _extractReferenceFiles(a);
                if (refFiles.isEmpty) return <Widget>[];
                return [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 3),
                        child: Text(l.t('reference_files').toUpperCase(), style: sectionCaptionStyle(context)),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(l.t('reference_files_hint'),
                            style: TextStyle(fontSize: 13, height: 1.35, color: detailText2(context))),
                      ),
                      FileList(
                        files: [for (final f in refFiles) FileEntry(name: fileDisplayName(f), url: f, previewUrl: f)],
                        onOpen: (f) => widget.onOpenFile(f.url, f.name),
                      ),
                    ]),
                  ),
                ];
              })(),

              // ── Ответ студента: текст + сетка миниатюр файлов ──
              if (sub != null && (sub['text_content'] != null || sub['file_urls'] != null))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: sectionCard(context, isDark, children: [
                    Text(l.t('your_answer'), style: cardTitleStyle(context)),
                    if (sub['text_content'] != null && sub['text_content'].toString().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(sub['text_content'],
                          style: TextStyle(fontSize: 16, height: 1.55, letterSpacing: -0.2, color: detailText2(context))),
                    ],
                    ...(() {
                      final urls = _parseFileUrls(sub['file_urls']);
                      if (urls.isEmpty) return <Widget>[];
                      return [
                        const SizedBox(height: 12),
                        _answerFileGrid(context, urls),
                      ];
                    })(),
                  ]),
                ),

              // ── Предварительная оценка: кольцо + текст + критерии, одной карточкой ──
              if (grade != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _assessmentCard(context, l, isDark, grade, criteriaScores, rubric, gradedByAi),
                )
              // ── Рубрика оценивания (учитель, пока никто не проверен) ──
              else if (widget.isTeacher && rubric.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _rubricPreviewCard(context, l, isDark, rubric),
                ),

              // ── Анализ ИИ: сильные / слабые стороны, две карточки рядом ──
              if (grade != null && gradedByAi) ..._aiAnalysisCards(context, l, criteriaScores),

              // ── Комментарий преподавателя ──
              if (grade != null && gradedByTeacher && (sub['grade']['feedback']?.toString().isNotEmpty ?? false))
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _teacherCommentSection(context, l, isDark, sub['grade']['feedback'].toString()),
                ),

              if (!widget.isTeacher && widget.viewOnly && sub == null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(color: detailSurface(context), borderRadius: BorderRadius.circular(AppRadii.card)),
                  child: Row(children: [
                    Icon(CupertinoIcons.lock_fill, size: 15, color: detailText2(context)),
                    const SizedBox(width: 9),
                    Expanded(child: Text(l.t('archive_readonly'),
                        style: TextStyle(fontSize: 15, letterSpacing: -0.2, color: detailText2(context), fontWeight: FontWeight.w500))),
                  ]),
                ),

              if (showSubmitBar) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(l.t('submit_work').toUpperCase(), style: sectionCaptionStyle(context)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: detailSurface(context),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.devicePixelRatioOf(context)),
                  ),
                  child: CupertinoTextField(
                    controller: _tc,
                    maxLines: 4,
                    placeholder: l.t('work_text_hint'),
                    placeholderStyle: TextStyle(color: detailText2(context), fontSize: 16, letterSpacing: -0.2),
                    style: TextStyle(fontSize: 16, height: 1.45, letterSpacing: -0.2, color: detailText1(context)),
                    padding: const EdgeInsets.all(15),
                    decoration: const BoxDecoration(),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: detailSurface(context),
                    borderRadius: BorderRadius.circular(AppRadii.card),
                    border: Border.all(
                      color: _pickedFiles.isEmpty ? detailBorder(context) : accent.withValues(alpha: 0.45),
                      width: _pickedFiles.isEmpty ? 1 / MediaQuery.devicePixelRatioOf(context) : 1,
                    ),
                  ),
                  child: Tappable(
                    onTap: () async {
                      final picked = await pickUploadFiles(context);
                      if (picked != null) setState(() => _pickedFiles = picked);
                    },
                    child: Row(children: [
                      Icon(CupertinoIcons.paperclip, color: accent, size: 19),
                      const SizedBox(width: 10),
                      Expanded(child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _pickedFiles.isEmpty ? l.t('attach_file') : '${l.t('files_selected')}: ${_pickedFiles.length}',
                          key: ValueKey(_pickedFiles.length),
                          style: TextStyle(fontSize: 16, letterSpacing: -0.2, color: _pickedFiles.isEmpty ? detailText2(context) : accent, fontWeight: _pickedFiles.isEmpty ? FontWeight.w500 : FontWeight.w600),
                        ),
                      )),
                      Icon(CupertinoIcons.chevron_right, color: detailText2(context).withValues(alpha: 0.8), size: 15),
                    ]),
                  ),
                ),
                if (_pickedFiles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final f in _pickedFiles) ...[
                    _pickedFileRow(context, isDark, f),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ),
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

  // ── Плавающая верхняя панель: круглые кнопки "назад" / меню ──
  Widget _topBar(BuildContext context, bool isDark) {
    return Row(children: [
      _circleButton(context, isDark, icon: CupertinoIcons.back, label: 'Назад', onTap: () => Navigator.pop(context)),
      const Spacer(),
      if (widget.isTeacher) _circleButton(context, isDark, icon: CupertinoIcons.ellipsis, label: 'Действия с заданием', onTap: _openMenu),
    ]);
  }

  Widget _circleButton(BuildContext context, bool isDark, {required IconData icon, required String label, required VoidCallback onTap}) {
    return Tappable(
      onTap: onTap,
      label: label,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40, height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: detailSurface(context),
          shape: BoxShape.circle,
          border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.devicePixelRatioOf(context)),
        ),
        child: Icon(icon, size: 19, color: detailText1(context)),
      ),
    );
  }

  Widget _titleBlock(BuildContext context, L10n l, dynamic grade) {
    final accent = detailAccent(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(CupertinoIcons.doc_text_fill, size: 12, color: accent),
            const SizedBox(width: 5),
            Text(l.t('task_badge').toUpperCase(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 7),
          Text(a['title'] ?? '',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: detailText1(context), letterSpacing: -0.7, height: 1.12)),
        ]),
      ),
      if (grade != null) ...[
        const SizedBox(width: 12),
        _headerScoreCard(context, grade),
      ],
    ]);
  }

  Widget _headerScoreCard(BuildContext context, dynamic grade) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: detailSurface(context),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: detailBorder(context), width: 1 / MediaQuery.devicePixelRatioOf(context)),
      ),
      child: Column(children: [
        Text('${grade['score']}',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: detailAccent(context), height: 1, letterSpacing: -0.8, fontFeatures: const [FontFeature.tabularFigures()])),
        Text('/ ${a['max_score']}',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: detailText2(context), fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  }

  Widget _statusChips(BuildContext context, L10n l, bool isLate) {
    final chips = <Widget>[];
    if (sub?['status'] == 'needs_review') {
      chips.add(_chip(l.t('needs_review'), CupertinoIcons.exclamationmark_circle_fill, C.amber));
    }
    if (isLate) {
      chips.add(_chip(l.t('overdue'), CupertinoIcons.clock_fill, C.red));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(String text, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(100)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color, letterSpacing: -0.1)),
      ]),
    );
  }

  Widget _dueReviewedRow(BuildContext context, L10n l, dynamic deadline, bool isLate, dynamic grade) {
    final gradedAt = grade?['graded_at']?.toString();
    final chunks = <Widget>[];
    if (deadline != null) {
      chunks.add(_metaChunk(context, CupertinoIcons.calendar, l.t('due_date'), _fmtDate(deadline), isLate ? C.red : null));
    }
    if (gradedAt != null && gradedAt.isNotEmpty) {
      chunks.add(_metaChunk(context, CupertinoIcons.clock, l.t('reviewed_label'), _fmtDate(gradedAt), null));
    }
    if (chunks.isEmpty) return const SizedBox.shrink();
    final withDividers = <Widget>[];
    for (var i = 0; i < chunks.length; i++) {
      if (i > 0) withDividers.add(Container(width: 1, height: 28, margin: const EdgeInsets.symmetric(horizontal: 14), color: detailBorder(context)));
      withDividers.add(chunks[i]);
    }
    return Row(children: withDividers);
  }

  Widget _metaChunk(BuildContext context, IconData icon, String label, String value, Color? valueColor) {
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 15, color: detailText2(context)),
      const SizedBox(width: 6),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 12, letterSpacing: 0.1, color: detailText2(context))),
        Text(value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: valueColor ?? detailText1(context))),
      ]),
    ]);
  }

  Widget _pendingBanner(BuildContext context, Color color, {required IconData icon, required String text, bool showSpinner = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showSpinner)
          SizedBox(width: 18, height: 18, child: CupertinoActivityIndicator(radius: 9, color: color))
        else
          Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text,
            style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.2, fontWeight: FontWeight.w600, color: color))),
      ]),
    );
  }

  Widget _answerFileGrid(BuildContext context, List<String> urls) {
    return LayoutBuilder(builder: (ctx, constraints) {
      const gap = 8.0;
      final tileWidth = (constraints.maxWidth - gap * 2) / 3;
      return Wrap(
        spacing: gap, runSpacing: gap,
        children: [
          for (final url in urls)
            SizedBox(width: tileWidth, child: _answerFileTile(context, url, tileWidth)),
        ],
      );
    });
  }

  Widget _answerFileTile(BuildContext context, String url, double width) {
    final name = fileDisplayName(url);
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final isImage = _imageExts.contains(ext);
    final visual = fileTypeVisual(ext);
    // Без memCacheWidth/Height CachedNetworkImage декодирует вложение в его
    // родном разрешении (фото с телефона — это легко 3000×4000px) ради
    // плитки ~100px в сетке до 3 в ряд — на экран ответа с несколькими
    // фото-вложениями это заметные лишние мегабайты в памяти и время на decode.
    final px = (width * MediaQuery.devicePixelRatioOf(context)).round();

    return Tappable(
      onTap: () => widget.onOpenFile(url, name),
      label: 'Открыть файл $name',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          child: isImage
              ? CachedNetworkImage(
                  imageUrl: url,
                  cacheKey: fileCacheKey(url),
                  memCacheWidth: px, memCacheHeight: px,
                  width: width, height: width, fit: BoxFit.cover,
                  placeholder: (_, __) => Container(width: width, height: width, color: detailSurface(context)),
                  errorWidget: (_, __, ___) => Container(width: width, height: width, color: visual.color.withValues(alpha: 0.14),
                      child: Icon(visual.icon, color: visual.color)),
                )
              : Container(
                  width: width, height: width,
                  color: visual.color.withValues(alpha: 0.14),
                  child: Icon(visual.icon, size: width * 0.32, color: visual.color),
                ),
        ),
        const SizedBox(height: 6),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: -0.2, color: detailText1(context))),
      ]),
    );
  }

  Widget _assessmentCard(BuildContext context, L10n l, bool isDark, dynamic grade, List<Map<String, dynamic>> criteriaScores, List<Map<String, dynamic>> rubric, bool gradedByAi) {
    final score = (grade['score'] as num?) ?? 0;
    final maxScore = (a['max_score'] as num?) ?? 100;
    final feedback = (grade['feedback']?.toString() ?? '').trim();
    final accent = detailAccent(context);

    return sectionCard(context, isDark, children: [
      Row(children: [
        Expanded(child: Text(l.t('preliminary_assessment'), style: cardTitleStyle(context))),
        if (gradedByAi)
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
        if (gradedByAi && feedback.isNotEmpty) ...[
          const SizedBox(width: 16),
          Expanded(child: Text(feedback,
              style: TextStyle(fontSize: 15, height: 1.45, letterSpacing: -0.2, color: detailText2(context)))),
        ],
      ]),
      if (criteriaScores.isNotEmpty) ...[
        const SizedBox(height: 22),
        Text(l.t('by_criteria').toUpperCase(), style: sectionCaptionStyle(context)),
        const SizedBox(height: 14),
        for (var i = 0; i < criteriaScores.length; i++) ...[
          _criteriaRow(context, criteriaScores[i], _rubricDescriptionFor((criteriaScores[i]['name'] ?? '').toString(), rubric)),
          if (i != criteriaScores.length - 1) ...[
            const SizedBox(height: 14),
            Container(height: 1 / MediaQuery.devicePixelRatioOf(context), color: detailBorder(context)),
            const SizedBox(height: 14),
          ],
        ],
      ],
    ]);
  }

  Widget _criteriaRow(BuildContext context, Map<String, dynamic> c, String? description) {
    final score = (c['score'] as num?) ?? 0;
    final max = (c['max'] as num?) ?? 0;
    final ratio = max > 0 ? (score.toDouble() / max.toDouble()).clamp(0.0, 1.0) : 0.0;
    final accent = detailAccent(context);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['name']?.toString() ?? '',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context))),
          if (description != null)
            Text(description, style: TextStyle(fontSize: 13, height: 1.3, color: detailText2(context))),
        ])),
        const SizedBox(width: 8),
        RichText(text: TextSpan(children: [
          TextSpan(text: '$score',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: accent, letterSpacing: -0.3, fontFeatures: const [FontFeature.tabularFigures()])),
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
                builder: (_, value, __) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: Container(color: accent),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  List<Widget> _aiAnalysisCards(BuildContext context, L10n l, List<Map<String, dynamic>> criteriaScores) {
    if (criteriaScores.isEmpty) return const [];
    final (strengths, weaknesses) = _splitStrengthsWeaknesses(criteriaScores);
    if (strengths.isEmpty && weaknesses.isEmpty) return const [];

    return [
      if (strengths.isNotEmpty) ...[
        _entranceCard(_bulletCard(context, title: l.t('strengths'), items: strengths, icon: CupertinoIcons.checkmark_circle_fill, color: C.green), 0),
        const SizedBox(height: 12),
      ],
      if (weaknesses.isNotEmpty) ...[
        _entranceCard(_bulletCard(context, title: l.t('areas_improve'), items: weaknesses, icon: CupertinoIcons.exclamationmark_triangle_fill, color: C.amber), 1),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 4),
    ];
  }

  // Мягкое появление секций (fade + едва заметный подъём).
  Widget _entranceCard(Widget child, int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 320 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (_, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: c)),
      child: child,
    );
  }

  Widget _bulletCard(BuildContext context, {required String title, required List<String> items, required IconData icon, required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(color: color.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.12 : 0.08), borderRadius: BorderRadius.circular(AppRadii.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(title.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.6)),
        ]),
        const SizedBox(height: 10),
        for (final item in items) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 5, height: 5, margin: const EdgeInsets.only(top: 8, right: 10),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              Expanded(child: Text(item,
                  style: TextStyle(fontSize: 15, height: 1.4, letterSpacing: -0.2, color: detailText1(context)))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _teacherCommentSection(BuildContext context, L10n l, bool isDark, String feedback) {
    return sectionCard(context, isDark, children: [
      Row(children: [
        Icon(CupertinoIcons.person_crop_circle_fill, size: 16, color: detailText2(context)),
        const SizedBox(width: 7),
        Text(l.t('teacher_comment').toUpperCase(), style: sectionCaptionStyle(context)),
      ]),
      const SizedBox(height: 10),
      Text(feedback,
          style: TextStyle(fontSize: 16, height: 1.55, letterSpacing: -0.2, color: detailText1(context))),
    ]);
  }

  // Рубрика оценивания видна учителю ещё до первой проверки — то же
  // содержимое (assignment.criteria), что позже станет "Оценка по критериям".
  Widget _rubricPreviewCard(BuildContext context, L10n l, bool isDark, List<Map<String, dynamic>> rubric) {
    final maxScore = (a['max_score'] as num?) ?? 100;
    final accent = detailAccent(context);
    return sectionCard(context, isDark, children: [
      Tappable(
        onTap: () => setState(() => _rubricExpanded = !_rubricExpanded),
        child: Row(children: [
          Icon(CupertinoIcons.list_bullet, size: 17, color: accent),
          const SizedBox(width: 9),
          Expanded(child: Text(l.t('criteria'), style: cardTitleStyle(context))),
          Text('${rubric.length}',
              style: TextStyle(fontSize: 15, color: detailText2(context), fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 7),
          AnimatedRotation(turns: _rubricExpanded ? 0.5 : 0.0, duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(CupertinoIcons.chevron_down, size: 15, color: accent)),
        ]),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: _rubricExpanded
            ? Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(children: [
                  for (var i = 0; i < rubric.length; i++) ...[
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(rubric[i]['name'] ?? '',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context))),
                        if ((rubric[i]['description'] ?? '').toString().isNotEmpty)
                          Text(rubric[i]['description'],
                              style: TextStyle(fontSize: 13, height: 1.3, color: detailText2(context))),
                      ])),
                      const SizedBox(width: 8),
                      Text('${rubric[i]['weight'] ?? 0} / $maxScore',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent, letterSpacing: -0.2, fontFeatures: const [FontFeature.tabularFigures()])),
                    ]),
                    if (i != rubric.length - 1) const SizedBox(height: 14),
                  ],
                ]),
              )
            : const SizedBox.shrink(),
      ),
    ]);
  }

  Widget _pickedFileRow(BuildContext context, bool isDark, PlatformFile f) {
    final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : '';
    final visual = fileTypeVisual(ext);
    final done = _uploadedNames.contains(f.name);
    final uploading = _uploadingName == f.name;
    final statusColor = done ? C.green : uploading ? detailAccent(context) : detailText2(context);

    return TweenAnimationBuilder<double>(
      key: ValueKey('${f.name}_${f.size}'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: done ? C.green.withValues(alpha: isDark ? 0.12 : 0.08) : detailSurface(context),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: done ? C.green.withValues(alpha: 0.3) : detailBorder(context),
            width: done ? 1 : 1 / MediaQuery.devicePixelRatioOf(context),
          ),
        ),
        child: Row(children: [
          Container(width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(color: visual.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadii.chip)),
            child: Icon(visual.icon, size: 17, color: visual.color)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.name,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: detailText1(context)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(_fmtBytes(f.size), style: TextStyle(fontSize: 13, color: detailText2(context))),
          ])),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: uploading
                ? SizedBox(key: const ValueKey('up'), width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: statusColor))
                : done
                    ? Icon(CupertinoIcons.checkmark_circle_fill, key: const ValueKey('done'), size: 20, color: statusColor)
                    : Tappable(
                        key: const ValueKey('rm'),
                        onTap: _busy ? null : () => setState(() => _pickedFiles.removeWhere((x) => x.name == f.name)),
                        label: 'Убрать файл ${f.name}',
                        child: Icon(CupertinoIcons.xmark_circle_fill, size: 20, color: detailText2(context).withValues(alpha: 0.5)),
                      ),
          ),
        ]),
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
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.82),
        border: Border(top: BorderSide(color: detailBorder(context), width: 1 / MediaQuery.devicePixelRatioOf(context))),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: AppButton(
          label: label,
          variant: secondary ? AppButtonVariant.secondary : AppButtonVariant.primary,
          color: secondary ? null : accent,
          background: secondary ? detailSurface(context) : null,
          onPressed: onTap,
          loading: busy,
          minHeight: 50,
        ),
      ),
        ),
      ),
    );
  }
}
