import 'dart:io';

import 'package:dio/dio.dart' show DioException;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/l10n_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tappable.dart';
import '../../widgets/toast.dart';

/// Полноэкранная форма создания класса — раньше была модальным `Dialog`
/// фиксированной высоты, где длинное описание или клавиатура обрезали форму.
/// Здесь, как и в lecture_editor_screen.dart, `PopScope` не даёт случайно
/// закрыть уже заполненную форму.
class CreateClassScreen extends StatefulWidget {
  const CreateClassScreen({super.key});

  @override
  State<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends State<CreateClassScreen> {
  final _nameC = TextEditingController();
  final _descC = TextEditingController();
  final _teacherC = TextEditingController();
  final _periodC = TextEditingController();
  XFile? _coverFile;
  bool _submitting = false;
  bool _dirty = false;

  @override
  void dispose() {
    _nameC.dispose();
    _descC.dispose();
    _teacherC.dispose();
    _periodC.dispose();
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

  Future<void> _pickCover() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (img == null) return;
    setState(() => _coverFile = img);
    _markDirty();
  }

  Future<void> _submit() async {
    final l = context.read<L10n>();
    if (_nameC.text.trim().isEmpty) {
      showToast(context, l.t('enter_class_name'), error: true);
      return;
    }
    setState(() => _submitting = true);
    final api = context.read<ApiService>();
    try {
      String? coverUrl;
      if (_coverFile != null) {
        final res = await api.uploadFile(_coverFile!.path, _coverFile!.name);
        coverUrl = (res['url'] ?? res['file_url'] ?? res['path'])?.toString();
      }
      final created = await api.createClass(_nameC.text.trim(),
          description: _descC.text.trim(),
          teacher: _teacherC.text.trim(),
          period: _periodC.text.trim(),
          coverImage: coverUrl);
      if (!mounted) return;
      _dirty = false;
      showToast(context, l.t('class_created'));
      Navigator.pop(context, created);
    } catch (e) {
      if (!mounted) return;
      final detail = (e is DioException && e.response?.data is Map) ? e.response?.data['detail'] : null;
      showToast(context, detail?.toString() ?? l.t('error'), error: true);
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<L10n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: isDark ? C.darkBg : C.bg,
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 20, 4),
                child: Row(children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.xmark, size: 20),
                    onPressed: () async {
                      if (await _confirmDiscard() && context.mounted) Navigator.pop(context);
                    },
                  ),
                  Expanded(child: Text(l.t('create_class_title'), textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: adaptiveText1(context)))),
                  const SizedBox(width: 40),
                ]),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 28),
                  children: [
                    Center(
                      child: Tappable(
                        onTap: _pickCover,
                        child: Stack(children: [
                          Container(
                            height: 180, width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadii.card),
                              color: _coverFile != null ? null : adaptiveSurface2(context),
                              border: _coverFile != null ? null : Border.all(color: adaptiveBorder(context), width: 1.5),
                            ),
                            child: _coverFile != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(AppRadii.card),
                                    child: Image.file(File(_coverFile!.path), fit: BoxFit.cover, width: double.infinity),
                                  )
                                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Container(width: 52, height: 52,
                                      decoration: BoxDecoration(color: adaptiveSurface2(context), shape: BoxShape.circle),
                                      child: Icon(CupertinoIcons.photo, size: 24, color: adaptiveText1(context))),
                                    const SizedBox(height: 12),
                                    Text(l.t('click_to_upload'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: adaptiveText1(context))),
                                    const SizedBox(height: 2),
                                    const Text('JPG, PNG', style: TextStyle(fontSize: 12, color: C.text4)),
                                  ]),
                          ),
                          if (_coverFile != null)
                            Positioned(right: 10, bottom: 10, child: Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(color: primary, shape: BoxShape.circle,
                                boxShadow: primaryGlow(primary, opacity: 0.3)),
                              child: const Icon(CupertinoIcons.pencil, size: 16, color: Colors.white),
                            )),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 28),

                    _label('${l.t('class_name_required')} *'),
                    TextField(
                      controller: _nameC,
                      decoration: InputDecoration(hintText: l.t('class_name_hint')),
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 18),

                    _label(l.t('class_desc')),
                    TextField(
                      controller: _descC,
                      decoration: InputDecoration(hintText: l.t('class_desc_hint')),
                      maxLines: 3,
                      onChanged: (_) => _markDirty(),
                    ),
                    const SizedBox(height: 18),

                    // Подписи и поля лежат в двух отдельных Row (а не парами
                    // внутри своих Column), чтобы разная длина слова
                    // "Период"/"Учитель" в разных языках не сдвигала поля
                    // ввода друг относительно друга по высоте — Row всегда
                    // берёт высоту самой высокой подписи для обеих колонок.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: _label(l.t('period_label'))),
                      const SizedBox(width: 14),
                      Expanded(child: _label(l.t('teacher_label'))),
                    ]),
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(
                        controller: _periodC,
                        decoration: InputDecoration(hintText: l.t('period_hint')),
                        onChanged: (_) => _markDirty(),
                      )),
                      const SizedBox(width: 14),
                      Expanded(child: TextField(
                        controller: _teacherC,
                        decoration: InputDecoration(hintText: l.t('your_name_hint')),
                        onChanged: (_) => _markDirty(),
                      )),
                    ]),
                    const SizedBox(height: 32),

                    Tappable(
                      onTap: _submitting ? null : _submit,
                      child: AnimatedContainer(duration: const Duration(milliseconds: 200),
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(AppRadii.tile),
                          boxShadow: _submitting ? null : primaryGlow(primary, opacity: 0.34),
                        ),
                        child: Align(heightFactor: 1, child: _submitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                          : Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                              const Icon(CupertinoIcons.plus, size: 17, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(l.t('create'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                            ])),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.text3)),
      );
}
