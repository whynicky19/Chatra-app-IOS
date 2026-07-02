import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/toast.dart';

/// Opens the "Create avatar lecture" bottom sheet. Returns true if a lecture
/// was successfully submitted (caller should refresh its lecture list).
Future<bool?> showCreateLectureSheet(BuildContext context, {required int classId}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _CreateLectureSheet(classId: classId),
  );
}

class _CreateLectureSheet extends StatefulWidget {
  final int classId;
  const _CreateLectureSheet({required this.classId});
  @override
  State<_CreateLectureSheet> createState() => _CreateLectureSheetState();
}

class _CreateLectureSheetState extends State<_CreateLectureSheet> {
  final _titleCtrl = TextEditingController();
  final _customDurationCtrl = TextEditingController();
  PlatformFile? _sourceFile;
  int _duration = 40;
  bool _customDuration = false;
  String _style = 'university';
  bool _autoSummary = true;
  bool _submitting = false;

  static const _durationOptions = [20, 40, 60, 80];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _customDurationCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _titleCtrl.text.trim().isNotEmpty && _sourceFile != null && _effectiveDuration != null && !_submitting;

  int? get _effectiveDuration {
    if (!_customDuration) return _duration;
    final v = int.tryParse(_customDurationCtrl.text.trim());
    if (v == null || v < 5 || v > 180) return null;
    return v;
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'pptx']);
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _sourceFile = result.files.first);
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l = context.read<L10n>();
    final api = context.read<ApiService>();
    setState(() => _submitting = true);
    try {
      final uploadRes = await api.uploadFile(_sourceFile!.path!, _sourceFile!.name);
      if (!mounted) return;
      final fileUrl = (uploadRes['url'] ?? uploadRes['file_url'] ?? uploadRes['path'])?.toString();
      if (fileUrl == null) throw Exception('upload_failed');

      await api.createAvatarLecture(
        classId: widget.classId,
        title: _titleCtrl.text.trim(),
        sourceFileUrl: fileUrl,
        sourceFilename: _sourceFile!.name,
        durationMinutes: _effectiveDuration!,
        style: _style,
        autoSummary: _autoSummary,
      );
      if (!mounted) return;
      showToast(context, l.t('lecture_created_toast'));
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) showToast(context, l.t('error'), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final primary = Theme.of(context).colorScheme.primary;
    final ext = (_sourceFile?.name.split('.').last ?? '').toUpperCase();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: adaptiveBorder(context), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            Container(width: 42, height: 42,
              decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(13)),
              child: Icon(CupertinoIcons.play_rectangle, color: primary, size: 22)),
            const SizedBox(width: 12),
            Expanded(child: Text(l.t('create_lecture_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            GestureDetector(onTap: () => Navigator.pop(context),
              child: Container(width: 32, height: 32, decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                child: const Icon(CupertinoIcons.xmark, size: 16, color: C.text4))),
          ]),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: adaptivePrimaryLt(context), borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(CupertinoIcons.info_circle_fill, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(child: Text(l.t('lecture_info_banner'), style: TextStyle(fontSize: 12.5, color: primary, height: 1.4))),
            ]),
          ),
          const SizedBox(height: 20),

          Text(l.t('lecture_title_label'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(controller: _titleCtrl, decoration: InputDecoration(hintText: l.t('lecture_title_hint')), onChanged: (_) => setState(() {})),
          const SizedBox(height: 20),

          Text(l.t('lecture_materials_label'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickFile,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: primary.withValues(alpha: 0.3))),
              child: _sourceFile == null
                  ? Column(children: [
                      Icon(CupertinoIcons.doc_richtext, size: 26, color: primary),
                      const SizedBox(height: 8),
                      Text(l.t('click_or_choose'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary)),
                      const SizedBox(height: 4),
                      Text(l.t('lecture_materials_hint'), style: const TextStyle(fontSize: 11, color: C.text4), textAlign: TextAlign.center),
                    ])
                  : Row(children: [
                      Container(width: 40, height: 40, decoration: BoxDecoration(color: primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Center(child: Text(ext, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: primary)))),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_sourceFile!.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(10)),
                        child: Text(l.t('lecture_materials_replace'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
            ),
          ),
          const SizedBox(height: 20),

          Text(l.t('duration'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ..._durationOptions.map((m) {
              final selected = !_customDuration && _duration == m;
              return GestureDetector(
                onTap: () => setState(() { _customDuration = false; _duration = m; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? primary : adaptiveSurface2(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$m ${l.t('minutes_suffix')}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : C.text3)),
                ),
              );
            }),
            GestureDetector(
              onTap: () => setState(() => _customDuration = true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: _customDuration ? primary : adaptiveSurface2(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(l.t('duration_custom'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _customDuration ? Colors.white : C.text3)),
              ),
            ),
          ]),
          if (_customDuration) Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextField(
              controller: _customDurationCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(hintText: '5–180', suffixText: l.t('minutes_suffix')),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 20),

          Text(l.t('style'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: C.text3, letterSpacing: 1)),
          const SizedBox(height: 8),
          _styleCard('school', l.t('style_school'), l.t('style_school_sub'), CupertinoIcons.book, primary),
          const SizedBox(height: 8),
          _styleCard('university', l.t('style_university'), l.t('style_university_sub'), CupertinoIcons.building_2_fill, primary),
          const SizedBox(height: 8),
          _styleCard('professional', l.t('style_professional'), l.t('style_professional_sub'), CupertinoIcons.briefcase_fill, primary),
          const SizedBox(height: 20),

          GestureDetector(
            onTap: () => setState(() => _autoSummary = !_autoSummary),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(_autoSummary ? CupertinoIcons.checkmark_square_fill : CupertinoIcons.square, color: _autoSummary ? primary : C.text4, size: 22),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.t('lecture_auto_summary'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text(l.t('lecture_auto_summary_sub'), style: const TextStyle(fontSize: 11, color: C.text4)),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(l.t('send_for_approval')),
          )),
        ]),
      ),
    );
  }

  Widget _styleCard(String value, String title, String sub, IconData icon, Color primary) {
    final selected = _style == value;
    return GestureDetector(
      onTap: () => setState(() => _style = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.1) : adaptiveSurface2(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? primary : Colors.transparent, width: 1.5),
        ),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: selected ? primary : adaptiveBorder(context), shape: BoxShape.circle),
            child: Icon(icon, color: selected ? Colors.white : C.text4, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: selected ? primary : null)),
            Text(sub, style: const TextStyle(fontSize: 11, color: C.text4)),
          ])),
          if (selected) Icon(CupertinoIcons.checkmark_circle_fill, color: primary, size: 20),
        ]),
      ),
    );
  }
}
