import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/upload_limits.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';
import 'class_detail_utils.dart' show cleanPostTitle, fileDisplayName;

/// Полноэкранная форма лекции — создание (`post == null`) и редактирование.
/// Раньше это была шторка (`showModalBottomSheet`): её можно было случайно
/// смахнуть вниз и потерять весь введённый текст, а клавиатура закрывала
/// половину полей. Здесь `PopScope` не даёт уйти с непустой формой без
/// подтверждения.
class LectureEditorScreen extends StatefulWidget {
  final int classId;
  final Map<String, dynamic>? post;

  const LectureEditorScreen({super.key, required this.classId, this.post});

  @override
  State<LectureEditorScreen> createState() => _LectureEditorScreenState();
}

class _LectureEditorScreenState extends State<LectureEditorScreen> {
  late final TextEditingController _titleC;
  late final TextEditingController _contentC;
  final List<String> _existingFiles = [];
  final List<PlatformFile> _newFiles = [];
  bool _submitting = false;
  bool _dirty = false;

  bool get _isEdit => widget.post != null;

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    String initialContent = '';
    if (p != null) {
      _titleC = TextEditingController(text: cleanPostTitle(p['title'] ?? ''));
      try {
        final body = jsonDecode(p['body'] as String) as Map<String, dynamic>;
        initialContent = body['content']?.toString() ?? '';
        if (body['files'] is List) {
          _existingFiles.addAll((body['files'] as List).map((f) => f.toString()));
        }
      } catch (_) {
        initialContent = p['body']?.toString() ?? '';
      }
    } else {
      _titleC = TextEditingController();
    }
    _contentC = TextEditingController(text: initialContent);
  }

  @override
  void dispose() {
    _titleC.dispose();
    _contentC.dispose();
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

  Future<void> _pickFiles() async {
    final picked = await pickUploadFiles(context,
        alreadyPicked: _existingFiles.length + _newFiles.length);
    if (picked == null) return;
    setState(() => _newFiles.addAll(picked));
    _markDirty();
  }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_titleC.text.trim().isEmpty) {
      showToast(context, l.t('enter_lecture_topic'), error: true);
      return;
    }
    setState(() => _submitting = true);
    final api = context.read<ApiService>();
    final prefix = '[LECTURE][${widget.classId}]';

    // Загрузка файлов идёт последовательно (не Future.wait) прямо перед
    // отправкой поста — параллельные multipart-потоки держат в памяти сразу
    // все файлы разом (риск OOM на бюджетных Android), а отправка на submit,
    // а не сразу при выборе файла, не оставляет сиротских загрузок на
    // сервере, если пользователь передумает и уйдёт с экрана.
    final fileUrls = <String>[...(_isEdit ? _existingFiles : const <String>[])];
    try {
      for (final pf in _newFiles) {
        final path = pf.path;
        if (path == null) continue;
        final res = await api.uploadFile(path, pf.name);
        final url = res['url'] ?? res['file_url'] ?? res['path'];
        if (url == null || url.toString().isEmpty) throw Exception('upload_failed');
        fileUrls.add('$url#${Uri.encodeComponent(pf.name)}');
      }
    } catch (_) {
      if (mounted) {
        showToast(context, l.t('upload_failed'), error: true);
        setState(() => _submitting = false);
      }
      return;
    }

    try {
      final body = jsonEncode({
        'content': _contentC.text,
        if (fileUrls.isNotEmpty) 'files': fileUrls,
      });
      if (_isEdit) {
        await api.updatePost(widget.post!['id'], '$prefix ${_titleC.text.trim()}', body);
      } else {
        await api.createPost('$prefix ${_titleC.text.trim()}', body);
      }
      if (!mounted) return;
      _dirty = false;
      Navigator.pop(context, true);
      showToast(context, l.t(_isEdit ? 'save_ok' : 'published'));
    } catch (_) {
      if (mounted) {
        showToast(context, l.t('error_generic'), error: true);
        setState(() => _submitting = false);
      }
    }
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
          title: Text(l.t(_isEdit ? 'edit_title' : 'add_lecture')),
          leading: IconButton(
            icon: const Icon(CupertinoIcons.xmark),
            tooltip: 'Закрыть',
            onPressed: () async {
              if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
            },
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
            children: [
              _label('${l.t('lecture_topic')} *'),
              TextField(
                controller: _titleC,
                decoration: InputDecoration(hintText: l.t('topic_hint')),
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 16),
              _label(l.t('lecture_content')),
              TextField(
                controller: _contentC,
                decoration: InputDecoration(hintText: l.t('content_body_hint')),
                maxLines: 6,
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 20),
              _label(l.t('attach_files')),
              if (_existingFiles.isNotEmpty) ...[
                for (final f in _existingFiles)
                  _fileRow(fileDisplayName(f), () {
                    setState(() => _existingFiles.remove(f));
                    _markDirty();
                  }),
                const SizedBox(height: 6),
              ],
              if (_newFiles.isNotEmpty) ...[
                for (final f in _newFiles)
                  _fileRow(f.name, () {
                    setState(() => _newFiles.remove(f));
                  }),
                const SizedBox(height: 6),
              ],
              Tappable(
                onTap: _submitting ? null : _pickFiles,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    border: Border.all(color: adaptiveBorder(context)),
                  ),
                  child: Column(children: [
                    const Icon(CupertinoIcons.arrow_up_doc, size: 24, color: C.text3),
                    const SizedBox(height: 6),
                    Text(l.t('click_or_choose'), style: TextStyle(fontSize: 13, color: adaptiveText3(context))),
                    Text(l.t('file_types_hint'), style: TextStyle(fontSize: 11, color: adaptiveText3(context))),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              AppButton.primary(
                label: l.t(_isEdit ? 'save' : 'publish'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: adaptiveSurface2(context), borderRadius: BorderRadius.circular(AppRadii.chip)),
        child: Row(children: [
          const Icon(CupertinoIcons.doc, size: 14, color: C.text3),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: const TextStyle(fontSize: 13, color: C.text3), overflow: TextOverflow.ellipsis)),
          Tappable(onTap: onRemove, label: 'Убрать файл', child: const Icon(CupertinoIcons.xmark, size: 14, color: C.text4)),
        ]),
      );
}
