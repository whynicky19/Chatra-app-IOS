import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dates.dart';
import '../../utils/upload_limits.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'class_detail_utils.dart' show cleanContent, fileDisplayName, fileUrlRe, mdFileRe;

/// Контроллеры критерия обязаны жить столько же, сколько сама строка, а не
/// пересоздаваться на каждой перестройке экрана — иначе TextField теряет
/// фокус и позицию курсора на каждое нажатие клавиши (было так в прежней
/// шторке, вынесено сюда как есть).
class _Criterion {
  String name;
  final TextEditingController nameC;

  _Criterion({this.name = ''}) : nameC = TextEditingController(text: name);

  void dispose() {
    nameC.dispose();
  }
}

/// Полноэкранная форма задания — создание (`assignment == null`) и
/// редактирование. Раньше это была шторка с полями заголовка, описания,
/// дедлайна, критериев и вложений — случайный свайп вниз стирал всё
/// введённое, а клавиатура закрывала половину формы.
class AssignmentEditorScreen extends StatefulWidget {
  final int classId;
  final Map<String, dynamic>? assignment;
  /// Только для редактирования — открывает шторку вариантов задания
  /// (короткий CRUD-список, для него шторка остаётся подходящим форматом).
  final void Function(int assignmentId)? onManageVariants;

  const AssignmentEditorScreen({
    super.key,
    required this.classId,
    this.assignment,
    this.onManageVariants,
  });

  @override
  State<AssignmentEditorScreen> createState() => _AssignmentEditorScreenState();
}

class _AssignmentEditorScreenState extends State<AssignmentEditorScreen> {
  late final TextEditingController _titleC;
  late final TextEditingController _descC;
  DateTime? _deadline;
  final List<String> _existingFiles = [];
  final List<PlatformFile> _newFiles = [];
  final List<PlatformFile> _referenceFiles = [];
  late List<_Criterion> _criteria;
  bool _submitting = false;
  bool _dirty = false;

  bool get _isEdit => widget.assignment != null;

  @override
  void initState() {
    super.initState();
    final a = widget.assignment;
    if (a != null) {
      _titleC = TextEditingController(text: a['title'] ?? '');
      final rawDesc = a['description']?.toString() ?? '';
      _descC = TextEditingController(text: cleanContent(rawDesc));
      _deadline = parseServerDate(a['deadline']);
      _existingFiles.addAll(_extractFileUrls(rawDesc));
      _criteria = _parseCriteria(a['criteria']);
    } else {
      _titleC = TextEditingController();
      _descC = TextEditingController();
      _criteria = [_Criterion()];
    }
  }

  List<String> _extractFileUrls(String text) {
    final result = <String>[];
    final seen = <String>{};
    for (final m in mdFileRe.allMatches(text)) {
      var url = m.group(2)!;
      if (!url.contains('#')) url = '$url#${Uri.encodeComponent(m.group(1)!)}';
      if (seen.add(url.split('#').first)) result.add(url);
    }
    for (final m in fileUrlRe.allMatches(text.replaceAll(mdFileRe, ''))) {
      final url = m.group(0)!;
      if (seen.add(url.split('#').first)) result.add(url);
    }
    return result;
  }

  List<_Criterion> _parseCriteria(dynamic raw) {
    try {
      final list = (jsonDecode(raw ?? '[]') as List?) ?? [];
      final parsed = list.map((c) => _Criterion(name: c['name'] ?? '')).toList();
      if (parsed.isNotEmpty) return parsed;
    } catch (_) {}
    return [_Criterion()];
  }

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    for (final c in _criteria) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final l = context.read<L10n>();
    final ok = await showConfirmDialog(
      context,
      title: l.t('discard_changes_title'),
      message: l.t('discard_changes_msg'),
      danger: true,
      confirmText: l.t('discard_changes_confirm'),
      cancelText: l.t('cancel'),
    );
    return ok == true;
  }

  Future<void> _pickDeadline() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _deadline?.hour ?? 23, minute: _deadline?.minute ?? 59),
    );
    if (!mounted) return;
    setState(() => _deadline = DateTime(d.year, d.month, d.day, t?.hour ?? 23, t?.minute ?? 59));
    _markDirty();
  }

  Future<void> _pickAttached() async {
    final picked = await pickUploadFiles(context,
        alreadyPicked: _existingFiles.length + _newFiles.length);
    if (picked == null) return;
    setState(() => _newFiles.addAll(picked));
    _markDirty();
  }

  Future<void> _pickReference() async {
    final picked = await pickUploadFiles(context, alreadyPicked: _referenceFiles.length);
    if (picked == null) return;
    setState(() => _referenceFiles.addAll(picked));
    _markDirty();
  }

  void _addCriterion() {
    setState(() => _criteria.add(_Criterion()));
    _markDirty();
  }

  void _removeCriterion(int i) {
    if (_criteria.length <= 1) return;
    setState(() => _criteria.removeAt(i).dispose());
    _markDirty();
  }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_titleC.text.trim().isEmpty) {
      showToast(context, l.t('enter_assignment_title'), error: true);
      return;
    }
    setState(() => _submitting = true);
    final api = context.read<ApiService>();

    final uploadedUrls = <String>[];
    try {
      for (final pf in [..._newFiles, if (!_isEdit) ..._referenceFiles]) {
        final path = pf.path;
        if (path == null) continue;
        final res = await api.uploadFile(path, pf.name);
        final url = res['url'] ?? res['file_url'] ?? res['path'];
        if (url == null || url.toString().isEmpty) throw Exception('upload_failed');
        uploadedUrls.add('$url#${Uri.encodeComponent(pf.name)}');
      }
    } catch (_) {
      if (mounted) {
        showToast(context, l.t('upload_failed'), error: true);
        setState(() => _submitting = false);
      }
      return;
    }

    final allUrls = [..._existingFiles, ...uploadedUrls]
        .map((u) => api.fixUrl(u))
        .toList();
    final cleanDesc = cleanContent(_descC.text.trim());
    final descWithFiles = allUrls.isEmpty
        ? cleanDesc
        : cleanDesc.isEmpty
            ? allUrls.join('\n')
            : '$cleanDesc\n${allUrls.join('\n')}';

    const maxScore = 100;
    final named = _criteria.where((c) => c.name.trim().isNotEmpty).toList();
    final finalCriteria = named.isEmpty
        ? [{'name': l.t('default_criterion'), 'weight': maxScore, 'description': ''}]
        : named.map((c) => {'name': c.name, 'weight': maxScore, 'description': ''}).toList();

    try {
      if (_isEdit) {
        await api.updateAssignment(widget.assignment!['id'], {
          'title': _titleC.text.trim(),
          'description': descWithFiles,
          'max_score': maxScore,
          'criteria': finalCriteria,
          if (_deadline != null) 'deadline': toServerDateString(_deadline!),
        });
      } else {
        await api.createAssignment({
          'class_id': widget.classId,
          'title': _titleC.text.trim(),
          'description': descWithFiles,
          'max_score': maxScore,
          'criteria': finalCriteria,
          if (_deadline != null) 'deadline': toServerDateString(_deadline!),
        });
      }
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
      showToast(context, l.t(_isEdit ? 'updated' : 'assignment_created'));
    } catch (e) {
      if (mounted) {
        showToast(context, '${l.t('error_generic')}: $e', error: true);
        setState(() => _submitting = false);
      }
    }
  }

  String _fmtDeadline(L10n l) {
    final d = _deadline;
    if (d == null) return l.t('deadline_placeholder');
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.t(_isEdit ? 'edit_assignment' : 'new_assignment')),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: () async {
              if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
            },
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
            children: [
              _label('${l.t('assignment_title')} *'),
              TextField(
                controller: _titleC,
                decoration: InputDecoration(hintText: l.t('assignment_title_hint')),
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 16),
              _label(l.t('assignment_desc')),
              TextField(
                controller: _descC,
                decoration: InputDecoration(hintText: l.t('assignment_desc_hint')),
                maxLines: 4,
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 16),
              _label(l.t('deadline')),
              Tappable(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).inputDecorationTheme.fillColor,
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                  child: Row(children: [
                    Text(_fmtDeadline(l),
                        style: TextStyle(fontSize: 15, color: _deadline != null ? null : C.text4)),
                    const Spacer(),
                    const Icon(CupertinoIcons.calendar, size: 18, color: C.text4),
                  ]),
                ),
              ),
              const SizedBox(height: 20),
              if (_existingFiles.isNotEmpty) ...[
                Row(children: [
                  Text(l.t('current_files'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
                  const Spacer(),
                  Text(l.t('tap_x_remove'), style: const TextStyle(fontSize: 11, color: C.text4)),
                ]),
                const SizedBox(height: 8),
                for (final url in _existingFiles)
                  _fileRow(fileDisplayName(url), () {
                    setState(() => _existingFiles.remove(url));
                    _markDirty();
                  }),
                const SizedBox(height: 12),
              ],
              Row(children: [
                Text(l.t('add_files_label'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
                const Spacer(),
                Tappable(
                  onTap: _pickAttached,
                  child: Text('+ ${l.t('add')}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                ),
              ]),
              const SizedBox(height: 8),
              if (_newFiles.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Theme.of(context).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
                  child: Row(children: [
                    const Icon(CupertinoIcons.paperclip, size: 15, color: C.text4),
                    const SizedBox(width: 8),
                    Text(l.t('no_new_files'), style: const TextStyle(fontSize: 13, color: C.text4)),
                  ]),
                )
              else
                for (final f in _newFiles)
                  _fileRow(f.name, () => setState(() => _newFiles.remove(f))),

              if (!_isEdit) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: adaptiveSurface2(context),
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    border: Border.all(color: adaptiveBorder(context)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 36, height: 36,
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
                        child: Icon(CupertinoIcons.checkmark_circle, size: 18, color: adaptiveText1(context))),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(l.t('reference_solutions'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadii.chip)),
                            child: Text(l.t('graded_by_ai'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                          ),
                        ]),
                        Text(l.t('reference_sub'), style: const TextStyle(fontSize: 11, color: C.text4)),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Tappable(
                      onTap: _pickReference,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.tile), border: Border.all(color: adaptiveBorder(context))),
                        child: Column(children: [
                          const Icon(CupertinoIcons.arrow_up_doc, size: 28, color: C.text3),
                          const SizedBox(height: 6),
                          Text(l.t('click_or_choose'), style: const TextStyle(fontSize: 13, color: C.text4)),
                          const Text('PDF, DOCX, DOC, PPTX, XLSX, TXT, MD', style: TextStyle(fontSize: 11, color: C.text4)),
                        ]),
                      ),
                    ),
                    if (_referenceFiles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final f in _referenceFiles)
                        _fileRow(f.name, () => setState(() => _referenceFiles.remove(f))),
                    ],
                  ]),
                ),
              ],

              const SizedBox(height: 20),
              Row(children: [
                Text(l.t('grading_criteria'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
                const Spacer(),
                Tappable(
                  onTap: _addCriterion,
                  child: Text('+ ${l.t('add')}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                ),
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < _criteria.length; i++) _criterionRow(i, l),

              if (_isEdit && widget.onManageVariants != null) ...[
                const SizedBox(height: 20),
                Tappable(
                  onTap: () => widget.onManageVariants!(widget.assignment!['id']),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
                    child: Row(children: [
                      Icon(CupertinoIcons.square_stack, size: 18, color: adaptiveText1(context)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(l.t('assignment_variants'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                      const Icon(CupertinoIcons.chevron_right, size: 16, color: C.text4),
                    ]),
                  ),
                ),
              ],

              const SizedBox(height: 28),
              AppButton.primary(
                label: l.t(_isEdit ? 'save' : 'create_assignment'),
                icon: _isEdit ? CupertinoIcons.checkmark : CupertinoIcons.plus,
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(s, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: adaptiveText3(context), letterSpacing: 1)),
      );

  Widget _fileRow(String name, VoidCallback onRemove) => Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.tile)),
        child: Row(children: [
          const Icon(CupertinoIcons.doc, size: 15, color: C.text3),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13, color: C.text3), overflow: TextOverflow.ellipsis)),
          Tappable(onTap: onRemove, label: 'Убрать файл', child: const Icon(CupertinoIcons.xmark, size: 15, color: C.red)),
        ]),
      );

  Widget _criterionRow(int i, L10n l) {
    final c = _criteria[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).inputDecorationTheme.fillColor, borderRadius: BorderRadius.circular(AppRadii.tile)),
      child: Row(children: [
        Text('${i + 1}', style: const TextStyle(fontSize: 13, color: C.text4)),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: c.nameC,
          decoration: InputDecoration(hintText: l.t('criterion_short'), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          onChanged: (v) { c.name = v; _markDirty(); },
        )),
        const SizedBox(width: 4),
        Tappable(onTap: () => _removeCriterion(i), label: 'Удалить критерий', child: const Icon(CupertinoIcons.xmark, size: 16, color: C.red)),
      ]),
    );
  }
}
